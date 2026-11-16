import request from '@ohos.request';
import { AppGlobal } from '../../app/AppGlobal';
import { Services } from '../../app/Services';
import {
  PptDeck,
  PptDeckDetail,
  PptDetailResult,
  PptFileInfo,
  PptListResult,
  PptChapter,
  PptMediaFile,
  PptSlide,
  downloadName,
  fileUrl,
  resolveUrl,
  formatBytes,
  pptStatusColor,
  pptStatusLabel
} from '../../data/ppt/PptModels';
import { Tokens } from '../theme/Tokens';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { PptUploadRepository } from '../../data/ppt/PptUploadRepository';
import { PptUploader } from '../../data/ppt/PptUploader';
import { Motion } from '../theme/Motion';
import { PageHeader } from '../components/PageHeader';

/**
 * 演示（PPT）工具：演示库列表（封面/状态/标签）+ 下载详情（兼容版 PPTX / PDF / 原始文件）。
 *
 * - 列表：`ppt_decks` 轻字段 + `manifest->files` 子查询；转换机心跳 180s 判在线；
 * - 下载：`request.downloadFile` 保存到应用文件目录（模拟器无 PowerPoint，不做打开）；
 * - 在线预览：分步图点按翻页、原样视频（章节跳转）、媒体单独下载、分片上传、本人软删除。
 */
@Component
export struct PptScreen {
  onClose: () => void = () => {
  };

  @State private decks: PptDeck[] = [];
  @State private agentOnline: boolean = false;
  @State private loading: boolean = true;
  @State private errorMsg: string = '';

  @State private detailOpen: boolean = false;
  @State private detailLoading: boolean = false;
  @State private detail: PptDeckDetail = new PptDeckDetail();
  @State private detailError: string = '';
  @State private notice: string = '';
  @State private downloading: string = '';
  @State private playerOpen: boolean = false;
  @State private playerSlide: number = 0;
  @State private playerStep: number = 0;
  @State private videoOpen: boolean = false;
  private videoController: VideoController = new VideoController();
  @State private uploading: boolean = false;
  @State private uploadDone: number = 0;
  @State private uploadTotal: number = 0;
  @State private uploadNotice: string = '';
  @State private lastSavedPath: string = '';
  @State private savingAs: boolean = false;
  @State private deleteConfirm: boolean = false;
  @State private deleteNotice: string = '';

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = this.decks.length === 0;
    this.errorMsg = '';
    const result: PptListResult = await Services.ppt.list();
    this.loading = false;
    if (!result.ok) {
      this.errorMsg = result.message;
      return;
    }
    this.decks = result.decks;
    this.agentOnline = result.agentOnline;
  }

  private closeDetail(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.detailOpen = false;
    });
  }

  private openDetail(deckId: string): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.detailOpen = true;
    });
    this.detailLoading = true;
    this.detailError = '';
    this.notice = '';
    this.loadDetail(deckId);
  }

  private async loadDetail(deckId: string): Promise<void> {
    const result: PptDetailResult = await Services.ppt.detail(deckId);
    this.detailLoading = false;
    if (!result.ok) {
      this.detailError = result.message;
      return;
    }
    this.detail = result.detail;
  }

  private imageUrl(ref: string): string {
    return resolveUrl(this.detail.base, ref);
  }

  private currentImage(): string {
    const slide: PptSlide | undefined = this.detail.slides[this.playerSlide];
    if (slide === undefined || slide.steps.length === 0) {
      return '';
    }
    const stepIndex: number = Math.min(this.playerStep, slide.steps.length - 1);
    return this.imageUrl(slide.steps[stepIndex].img);
  }

  private playerLabel(): string {
    const count: number = this.detail.slides.length > 0 ? this.detail.slides.length : 0;
    const slide: PptSlide | undefined = this.detail.slides[this.playerSlide];
    const steps: number = slide !== undefined ? slide.steps.length : 0;
    return (this.playerSlide + 1) + ' / ' + count + (steps > 1 ? ' · 步 ' + (this.playerStep + 1) + '/' + steps : '');
  }

  private nextStep(): void {
    const slide: PptSlide | undefined = this.detail.slides[this.playerSlide];
    if (slide === undefined) {
      return;
    }
    if (this.playerStep + 1 < slide.steps.length) {
      this.playerStep += 1;
    } else if (this.playerSlide + 1 < this.detail.slides.length) {
      this.playerSlide += 1;
      this.playerStep = 0;
    }
  }

  private prevStep(): void {
    if (this.playerStep > 0) {
      this.playerStep -= 1;
    } else if (this.playerSlide > 0) {
      this.playerSlide -= 1;
      const prev: PptSlide | undefined = this.detail.slides[this.playerSlide];
      this.playerStep = prev !== undefined ? Math.max(0, prev.steps.length - 1) : 0;
    }
  }

  private openPlayer(): void {
    this.playerSlide = 0;
    this.playerStep = 0;
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.playerOpen = true;
    });
  }

  private closePlayer(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.playerOpen = false;
    });
  }

  private openVideo(): void {
    this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
      this.videoOpen = true;
    });
  }

  private closeVideo(): void {
    this.getUIContext().animateTo({ duration: Motion.FAST, curve: Motion.ease() }, () => {
      this.videoOpen = false;
    });
  }

  private async downloadMedia(file: PptMediaFile): Promise<void> {
    const info: PptFileInfo = new PptFileInfo();
    info.s = file.s;
    info.name = file.name;
    info.size = file.size;
    const dot: number = file.name.lastIndexOf('.');
    info.ext = dot >= 0 ? file.name.substring(dot + 1) : '';
    await this.download(this.detail.deck, info, 'media');
  }

  private async softDeleteDeck(): Promise<void> {
    if (this.detail.deck.id.length === 0) {
      return;
    }
    if (!this.deleteConfirm) {
      this.deleteConfirm = true;
      this.deleteNotice = '再点一次「删除演示」确认（仅对自己上传的演示生效）';
      setTimeout(() => {
        this.deleteConfirm = false;
      }, 3000);
      return;
    }
    this.deleteConfirm = false;
    const ok: boolean = await Services.ppt.softDelete(this.detail.deck.id, Date.now());
    if (ok) {
      this.closeDetail();
      await this.reload();
      this.uploadNotice = '已删除该演示';
    } else {
      this.deleteNotice = '删除失败（只能删除本人上传的演示）';
    }
  }

  private canDelete(): boolean {
    const owner: string = this.detail.deck.ownerSid;
    if (owner.length > 0 && Services.currentSid.length > 0) {
      return owner === Services.currentSid;
    }
    return this.detail.deck.ownerName.length > 0 && this.detail.deck.ownerName === Services.currentName;
  }

  private async saveAs(): Promise<void> {
    if (this.savingAs || this.lastSavedPath.length === 0) {
      return;
    }
    const context = AppGlobal.context;
    if (context === undefined) {
      this.notice = '应用上下文缺失';
      return;
    }
    const slash: number = this.lastSavedPath.lastIndexOf('/');
    const name: string = slash >= 0 ? this.lastSavedPath.substring(slash + 1) : 'deck.pptx';
    this.savingAs = true;
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        this.notice = '已取消保存';
        this.savingAs = false;
        return;
      }
      const src: fs.File = fs.openSync(this.lastSavedPath, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(src.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(src.fd, buffer);
      fs.closeSync(src);
      const dest: fs.File = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(dest.fd, buffer);
      fs.closeSync(dest);
      this.notice = '已保存到文件：' + name;
    } catch (e) {
      this.notice = '保存到文件失败';
    }
    this.savingAs = false;
  }

  private async pickAndUpload(): Promise<void> {
    if (this.uploading) {
      return;
    }
    const context = AppGlobal.context;
    if (context === undefined) {
      this.uploadNotice = '无法打开文件选择器';
      return;
    }
    let uris: string[] = [];
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pptx', '.ppt'];
      uris = await documentPicker.select(options);
    } catch (e) {
      this.uploadNotice = '打开文件选择器失败';
      return;
    }
    if (uris.length === 0) {
      return;
    }
    const uri: string = uris[0];
    const encodedName: string = uri.substring(uri.lastIndexOf('/') + 1);
    let name: string = encodedName;
    try {
      name = decodeURIComponent(encodedName);
    } catch (e) {
      name = encodedName;
    }
    this.uploading = true;
    this.uploadDone = 0;
    this.uploadTotal = 0;
    this.uploadNotice = '正在上传 ' + name;
    const uploader: PptUploader = new PptUploader(new PptUploadRepository(Services.api),
      Services.currentSid, Services.currentName);
    const error: string = await uploader.upload(uri, name, (done: number, total: number) => {
      this.uploadDone = done;
      this.uploadTotal = total;
    });
    this.uploading = false;
    if (error.length === 0) {
      this.uploadNotice = '已上传并排队转换，完成后下拉刷新';
      this.reload();
    } else {
      this.uploadNotice = error;
    }
  }

  private async download(deck: PptDeck, file: PptFileInfo, kind: string): Promise<void> {
    const url: string = fileUrl(this.detail.base, file);
    if (url.length === 0) {
      this.notice = '该文件暂无可下载地址';
      return;
    }
    const name: string = file.name.length > 0 ? file.name : downloadName(deck, file, kind);
    this.downloading = name;
    this.notice = '开始下载 ' + name + '…';
    try {
      const context = AppGlobal.context;
      if (context === undefined) {
        this.notice = '应用上下文缺失，无法下载';
        this.downloading = '';
        return;
      }
      const target: string = context.filesDir + '/' + name;
      try {
        if (fs.accessSync(target)) {
          fs.unlinkSync(target);
        }
      } catch (e) {
        // 忽略清理失败，继续下载
      }
      await request.downloadFile(context, {
        url: url,
        filePath: target,
        enableMetered: true,
        background: false
      });
      this.lastSavedPath = target;
      this.notice = '已下载到应用目录，可点「保存到文件」导出';
    } catch (e) {
      this.notice = '下载失败，请稍后重试';
    }
    this.downloading = '';
  }

  @Builder
  tag(text: string, color: string) {
    Text(text)
      .fontSize(Tokens.F_CAPTION)
      .fontColor(color)
      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
      .backgroundColor(Tokens.tint(color, 0.12))
      .borderRadius(6)
      .margin({ right: 4 })
  }

  @Builder
  deckCard(deck: PptDeck) {
    Row() {
      if (deck.coverUrl.length > 0) {
        Image(deck.coverUrl)
          .width(96)
          .height(54)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(Tokens.BG)
      } else {
        Column()
          .width(96)
          .height(54)
          .borderRadius(8)
          .backgroundColor(Tokens.BG)
      }

      Column() {
        Text(deck.title.length > 0 ? deck.title : '未命名演示')
          .fontSize(Tokens.F_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 6 }) {
          this.tag(pptStatusLabel(deck.status), pptStatusColor(deck.status))
          if (deck.slideCount > 0) {
            this.tag(deck.slideCount + ' 页', Tokens.TEXT_SECONDARY)
          }
          if (deck.hasCompat) {
            this.tag('兼容版', Tokens.MIST_TEAL)
          }
          if (deck.hasPdf) {
            this.tag('PDF', Tokens.SLATE_BLUE)
          }
          Blank()
        }
        .width('100%')
        .margin({ top: 4 })

        Text((deck.ownerName.length > 0 ? deck.ownerName + ' · ' : '') + formatBytes(deck.sourceSize))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .onClick(() => {
      this.openDetail(deck.id);
    })
  }

  @Builder
  fileRow(deck: PptDeck, file: PptFileInfo | undefined, kind: string, label: string, hint: string) {
    Row() {
      Column() {
        Text(label)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
        Text(file !== undefined
          ? (formatBytes(file.size) + (file.pages > 0 ? ' · ' + file.pages + ' 页' : ''))
          : '未生成')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 2 })
        if (hint.length > 0) {
          Text(hint)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(file !== undefined ? (this.downloading.length > 0 ? '下载中…' : '下载') : '—')
        .height(34)
        .fontSize(Tokens.F_CAPTION)
        .backgroundColor(file !== undefined ? Tokens.MIST_TEAL : Tokens.BG)
        .fontColor(file !== undefined ? '#FFFFFF' : Tokens.TEXT_TERTIARY)
        .borderRadius(Tokens.RADIUS_PILL)
        .enabled(file !== undefined && this.downloading.length === 0)
        .onClick(() => {
          if (file !== undefined) {
            this.download(deck, file, kind);
          }
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  detailPanel() {
    Column() {
      Row() {
        Text('演示下载')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('关闭')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.SLATE_BLUE)
          .onClick(() => {
            this.closeDetail();
          })
      }
      .width('100%')

      if (this.detailLoading) {
        Text('加载中…')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 10 })
      } else if (this.detail.deck.id.length === 0) {
        Text(this.detailError.length > 0 ? this.detailError : '演示不存在')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.DANGER)
          .margin({ top: 10 })
      } else {
        Scroll() {
          Column() {
            Text(this.detail.deck.title)
              .fontSize(Tokens.F_TITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(Tokens.TEXT_PRIMARY)
              .width('100%')
            Text((this.detail.deck.ownerName.length > 0 ? this.detail.deck.ownerName + ' · ' : '')
              + this.detail.deck.slideCount + ' 页')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .margin({ top: 4 })



            Column() {
              this.fileRow(this.detail.deck, this.detail.files.compat, 'compat', '兼容版 PPTX', '推荐：已修复媒体链接')
              Divider().color(Tokens.DIVIDER)
              this.fileRow(this.detail.deck, this.detail.files.pdf, 'pdf', '预览 PDF', '')
              Divider().color(Tokens.DIVIDER)
              this.fileRow(this.detail.deck, this.detail.files.source, 'source', '原始文件', '保留原样，仅供参考')
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
            .margin({ top: 10 })
            .backgroundColor(Tokens.BG)
            .borderRadius(Tokens.RADIUS_CARD)

            if (this.detail.warnings.length > 0) {
              Column() {
                ForEach(this.detail.warnings, (warning: string) => {
                  Text('· ' + warning)
                    .fontSize(Tokens.F_CAPTION)
                    .fontColor(Tokens.WARM_SAND)
                    .width('100%')
                    .margin({ top: 2 })
                }, (warning: string, index: number) => 'warn_' + index)
              }
              .width('100%')
              .margin({ top: 8 })
            }

            if (this.detail.slides.length > 0) {
              Button('在线预览（分步图）')
                .width('100%')
                .height(42)
                .margin({ top: 10 })
                .backgroundColor(Tokens.SLATE_BLUE)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.openPlayer();
                })
            }
            if (this.detail.video !== undefined) {
              Button('原样播放（视频）')
                .width('100%')
                .height(42)
                .margin({ top: 8 })
                .backgroundColor(Tokens.MIST_TEAL)
                .fontColor('#FFFFFF')
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.openVideo();
                })
            }
            if (this.detail.mediaFiles.length > 0) {
              Text('视频 / 音频单独下载')
                .fontSize(Tokens.F_LABEL)
                .fontWeight(FontWeight.Medium)
                .fontColor(Tokens.TEXT_PRIMARY)
                .width('100%')
                .margin({ top: 12 })
              Column() {
                ForEach(this.detail.mediaFiles, (file: PptMediaFile) => {
                  Row() {
                    Text(file.name)
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_PRIMARY)
                      .layoutWeight(1)
                      .maxLines(2)
                    Text(formatBytes(file.size))
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.TEXT_TERTIARY)
                      .margin({ left: 8 })
                    Text('下载')
                      .fontSize(Tokens.F_CAPTION)
                      .fontColor(Tokens.SLATE_BLUE)
                      .margin({ left: 10 })
                      .onClick(() => {
                        this.downloadMedia(file);
                      })
                  }
                  .width('100%')
                  .padding({ top: 6, bottom: 6 })
                }, (file: PptMediaFile) => 'media_' + file.s)
              }
              .width('100%')
              .padding({ left: 12, right: 12 })
              .margin({ top: 6 })
              .backgroundColor(Tokens.BG)
              .borderRadius(Tokens.RADIUS_CARD)
            }

            if (this.canDelete()) {
              Button(this.deleteConfirm ? '确认删除？' : '删除演示')
                .width('100%')
                .height(40)
                .margin({ top: 10 })
                .backgroundColor(Tokens.BG)
                .fontColor(Tokens.DANGER)
                .borderRadius(Tokens.RADIUS_PILL)
                .onClick(() => {
                  this.softDeleteDeck();
                })
            }
            if (this.deleteNotice.length > 0) {
              Text(this.deleteNotice)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.WARM_SAND)
                .width('100%')
                .margin({ top: 6 })
            }

            if (this.lastSavedPath.length > 0) {
              Button(this.savingAs ? '保存中…' : '保存到文件（导出到系统文件）')
                .width('100%')
                .height(40)
                .margin({ top: 10 })
                .backgroundColor(Tokens.BG)
                .fontColor(Tokens.SLATE_BLUE)
                .borderRadius(Tokens.RADIUS_PILL)
                .enabled(!this.savingAs)
                .onClick(() => {
                  this.saveAs();
                })
            }
            if (this.notice.length > 0) {
              Text(this.notice)
                .fontSize(Tokens.F_CAPTION)
                .fontColor(Tokens.MIST_TEAL)
                .width('100%')
                .margin({ top: 8 })
            }
          }
          .width('100%')
          .padding({ bottom: 12 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('76%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .transition(TransitionEffect.asymmetric(Motion.sheetEnter(), Motion.sheetExit()))
  }

  build() {
    Stack() {
      Column() {
        PageHeader({
          title: '演示',
          actionText: this.loading ? '' : '刷新',
          onBack: () => {
            this.onClose();
          },
          onAction: () => {
            this.reload();
          }
        })

        Row() {
          Text((this.agentOnline ? '转换机在线' : '转换机离线（只能下载已转换文件）')
            + ' · ' + this.decks.length + ' 个演示')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.agentOnline ? Tokens.MIST_TEAL : Tokens.WARM_SAND)
            .layoutWeight(1)
          if (this.uploading) {
            Text(this.uploadTotal > 0 ? '上传中 ' + this.uploadDone + '/' + this.uploadTotal : '上传中…')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
          } else {
            Text('上传')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.SLATE_BLUE)
              .padding({ left: 8, right: 2 })
              .onClick(() => {
                this.pickAndUpload();
              })
          }
        }
        .width('100%')
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })

        if (this.uploadNotice.length > 0) {
          Text(this.uploadNotice)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 4 })
        }

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color(Tokens.MIST_TEAL)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.DANGER)
              .width('100%')
              .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, top: 8 })
          }
          if (this.decks.length === 0) {
            Text('暂无演示')
              .fontSize(Tokens.F_LABEL)
              .fontColor(Tokens.TEXT_TERTIARY)
              .width('100%')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          } else {
            List({ space: 10 }) {
              ForEach(this.decks, (deck: PptDeck) => {
                ListItem() {
                  this.deckCard(deck)
                }
              }, (deck: PptDeck) => deck.id + '_' + deck.status + '_' + (deck.hasCompat ? '1' : '0') + (deck.hasPdf ? '1' : '0'))
            }
            .width('100%')
            .layoutWeight(1)
            .margin({ top: 10 })
            .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
            .scrollBar(BarState.Off)
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Tokens.BG)

      if (this.detailOpen) {
        Column() {
          this.detailPanel()
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .justifyContent(FlexAlign.End)
        .transition(Motion.scrim())
        .animation({ duration: Motion.NORMAL, curve: Motion.ease() })
      }

      if (this.playerOpen) {
        Stack({ alignContent: Alignment.TopStart }) {
          Image(this.currentImage())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .backgroundColor('#000000')
          Row() {
            Column()
              .layoutWeight(3)
              .height('100%')
              .onClick(() => {
                this.prevStep();
              })
            Column()
              .layoutWeight(4)
              .height('100%')
            Column()
              .layoutWeight(3)
              .height('100%')
              .onClick(() => {
                this.nextStep();
              })
          }
          .width('100%')
          .height('100%')
          Row() {
            Text('关闭')
              .fontSize(Tokens.F_LABEL)
              .fontColor('#FFFFFF')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                this.closePlayer();
              })
            Blank()
            Text(this.playerLabel())
              .fontSize(Tokens.F_CAPTION)
              .fontColor('#FFFFFF')
              .padding({ right: 16 })
          }
          .width('100%')
          .height(56)
          .backgroundColor('#99000000')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .transition(Motion.scrim())
      }

      if (this.videoOpen) {
        Stack({ alignContent: Alignment.TopStart }) {
          Video({
            src: this.detail.video !== undefined ? this.imageUrl(this.detail.video.src) : '',
            controller: this.videoController
          })
            .autoPlay(true)
            .controls(true)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .backgroundColor('#000000')
          Row() {
            Text('关闭')
              .fontSize(Tokens.F_LABEL)
              .fontColor('#FFFFFF')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                this.closeVideo();
              })
            Blank()
            Text('原样播放')
              .fontSize(Tokens.F_CAPTION)
              .fontColor('#FFFFFF')
              .padding({ right: 16 })
          }
          .width('100%')
          .height(56)
          .backgroundColor('#99000000')

          if (this.detail.video !== undefined && this.detail.video.chapterList.length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.detail.video.chapterList, (chapter: PptChapter) => {
                  Text(chapter.title.length > 0 ? chapter.title : ('第 ' + (chapter.index + 1) + ' 章'))
                    .fontSize(11)
                    .fontColor('#FFFFFF')
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .backgroundColor('#33FFFFFF')
                    .borderRadius(12)
                    .onClick(() => {
                      this.videoController.setCurrentTime(chapter.startSec);
                    })
                }, (chapter: PptChapter) => 'ch_' + chapter.index)
              }
            }
            .width('100%')
            .height(36)
            .margin({ top: 56 })
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .padding({ left: 12 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .transition(Motion.scrim())
      }
    }
    .width('100%')
    .height('100%')
  }
}
