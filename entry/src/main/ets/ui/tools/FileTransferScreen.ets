import { Services } from '../../app/Services';
import { CloudSpaceFile, CloudSpaceSnapshot, CloudSpaceResult } from '../../data/cloudspace/CloudSpaceModels';
import { CloudSpaceLogic } from '../../data/cloudspace/CloudSpaceLogic';
import { CloudSpaceRepository, PickedFile } from '../../data/cloudspace/CloudSpaceRepository';
import { Tokens } from '../theme/Tokens';
import { Breakpoints } from '../theme/Breakpoints';

/**
 * 文件传输 / 临时云空间（对齐网页 `#s-file`、安卓 CloudSpaceScreen）。
 *
 * - 同班级身份（同 sid）跨设备自动共享同一空间，不需要房间码/配对；
 * - ECS drop v2.2：8 MiB 分片上传任意大小文件、列表/下载/删除/清空；
 * - **每个文件自上传完成起保留 72 小时**（逐文件过期），下载链接每次读取重签（30 分钟有效）；
 * - 文件选择用系统 `DocumentViewPicker`；下载落应用沙箱并用系统能力打开；
 * - 班级 token 只在请求头 `X-Device-Id` 中出现，不落盘/不打印。
 */
@Component
export struct FileTransferScreen {
  onClose: () => void = () => {
  };

  @State private loading: boolean = true;
  @State private connected: boolean = false;
  @State private files: CloudSpaceFile[] = [];
  @State private expiredCount: number = 0;
  @State private statusMsg: string = '';
  @State private errorMsg: string = '';
  @State private uploading: boolean = false;
  @State private uploadName: string = '';
  @State private uploadPercent: number = 0;
  @State private uploadStateText: string = '';
  @State private downloadingId: string = '';
  @State private layoutWidth: number = 0;
  private pollTimer: number = -1;
  private repo(): CloudSpaceRepository {
    return Services.cloudspace;
  }

  aboutToAppear(): void {
    this.refresh(true);
    this.pollTimer = setInterval(() => {
      if (!this.uploading) {
        this.refresh(false);
      }
    }, 5000);
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private applySnapshot(snapshot: CloudSpaceSnapshot): void {
    this.connected = snapshot.connected();
    this.files = snapshot.files;
    this.expiredCount = snapshot.expiredCount;
    this.loading = false;
  }

  private async refresh(force: boolean): Promise<void> {
    if (Services.currentToken.length === 0) {
      this.loading = false;
      this.errorMsg = '身份缺失，请重新登录';
      return;
    }
    const result: CloudSpaceResult<CloudSpaceSnapshot> = force
      ? await this.repo().ensureSpace() : await this.repo().refresh(false);
    if (result.ok && result.value !== undefined) {
      this.applySnapshot(result.value);
      if (force) {
        this.errorMsg = '';
      }
      return;
    }
    this.loading = false;
    this.errorMsg = result.error !== undefined ? result.error.displayMessage() : '云空间加载失败，请稍后重试';
  }

  private async pickAndUpload(): Promise<void> {
    if (this.uploading) {
      return;
    }
    this.errorMsg = '';
    const picked: PickedFile | undefined = await this.repo().pickFile();
    if (picked === undefined) {
      return;
    }
    if (picked.sizeBytes <= 0) {
      this.errorMsg = '空文件无法上传（0 字节）';
      return;
    }
    this.uploading = true;
    this.uploadName = picked.name;
    this.uploadPercent = 0;
    this.uploadStateText = '准备上传…';
    const result: CloudSpaceResult<CloudSpaceFile> = await this.repo().upload(picked,
      (progress) => {
        this.uploadPercent = CloudSpaceLogic.uploadPercent(progress.sentBytes, progress.totalBytes);
        this.uploadStateText = CloudSpaceLogic.uploadStateText(progress.state, progress.message);
      });
    this.uploading = false;
    if (result.ok) {
      this.uploadPercent = 100;
      this.uploadStateText = '已上传';
      this.statusMsg = '已上传「' + CloudSpaceLogic.safeName(picked.name) + '」· 保留 72 小时';
      await this.refresh(true);
    } else {
      this.errorMsg = result.error !== undefined ? result.error.displayMessage() : '上传失败，请重试';
    }
  }

  private async downloadFile(file: CloudSpaceFile): Promise<void> {
    if (this.downloadingId.length > 0) {
      return;
    }
    this.downloadingId = file.id;
    this.errorMsg = '';
    this.statusMsg = '正在下载「' + file.name + '」…';
    const result: CloudSpaceResult<string> = await this.repo().download(file,
      (received: number, total: number) => {
        this.uploadStateText = '下载中 ' + CloudSpaceLogic.uploadPercent(received, total) + '%';
      });
    if (!result.ok || result.value === undefined) {
      this.downloadingId = '';
      this.statusMsg = '';
      this.errorMsg = result.error !== undefined ? result.error.displayMessage() : '下载失败，请重试';
      return;
    }
    const path: string = result.value;
    const openError: string = await this.repo().openLocalFile(path, file.mimeType);
    this.downloadingId = '';
    this.statusMsg = openError.length > 0 ? openError : '已下载并打开「' + file.name + '」';
  }

  private confirmDelete(file: CloudSpaceFile): void {
    AlertDialog.show({
      title: '删除文件',
      message: '「' + file.name + '」将从同账号所有设备移除，删除后不可恢复。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Tokens.DANGER,
        action: () => {
          this.deleteFile(file);
        }
      }
    });
  }

  private async deleteFile(file: CloudSpaceFile): Promise<void> {
    const result = await this.repo().delete(file.id);
    if (result.ok && result.value !== undefined) {
      this.applySnapshot(result.value);
      this.statusMsg = '已删除「' + file.name + '」';
    } else {
      this.errorMsg = result.error !== undefined ? result.error.displayMessage() : '删除失败，请重试';
    }
  }

  private confirmClear(): void {
    AlertDialog.show({
      title: '清空云空间',
      message: '将删除本账号云空间内的全部文件（同账号所有设备）并重新开一个空空间。',
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清空',
        fontColor: Tokens.DANGER,
        action: () => {
          this.clearSpace();
        }
      }
    });
  }

  private async clearSpace(): Promise<void> {
    this.loading = true;
    const result = await this.repo().clearSpace();
    this.loading = false;
    if (result.ok && result.value !== undefined) {
      this.applySnapshot(result.value);
      this.statusMsg = '已清空云空间';
    } else {
      this.errorMsg = result.error !== undefined ? result.error.displayMessage() : '清空失败，请重试';
    }
  }

  private fileMeta(file: CloudSpaceFile): string {
    const parts: string[] = [];
    parts.push(CloudSpaceLogic.fmtSize(file.sizeBytes));
    const time: string = CloudSpaceLogic.fmtTime(file.uploadedAt);
    if (time.length > 0) {
      parts.push(time);
    }
    parts.push(CloudSpaceLogic.ttlText(file.uploadedAt, Date.now()));
    return parts.join(' · ');
  }

  private contentMax(): number {
    return Breakpoints.contentMaxWidth(this.layoutWidth);
  }

  @Builder
  header() {
    Row() {
      Text('‹')
        .fontSize(28)
        .fontColor(Tokens.TEXT_PRIMARY)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onClose();
        })
        .accessibilityText('返回')

      Text('文件传输')
        .fontSize(Tokens.F_HEADING)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.TEXT_PRIMARY)
        .layoutWeight(1)

      Text('刷新')
        .fontSize(Tokens.F_LABEL)
        .fontColor(Tokens.MIST_TEAL)
        .padding({ left: 8, right: 10 })
        .height(44)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.refresh(true);
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 8 })
    .backgroundColor(Tokens.BG)
  }

  @Builder
  uploadBar() {
    Column() {
      Row() {
        Text('临时云空间')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('保留 72 小时 · 同账号跨设备')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')

      Text('上传的文件自完成起 3 天后自动删除；不限制文件大小（8 MiB 分片）。')
        .fontSize(Tokens.F_CAPTION)
        .fontColor(Tokens.TEXT_TERTIARY)
        .width('100%')
        .margin({ top: 4 })

      Button(this.uploading ? '上传中…' : '选择文件上传')
        .width('100%')
        .height(44)
        .margin({ top: 10 })
        .backgroundColor(this.uploading ? Tokens.TEXT_TERTIARY : Tokens.MIST_TEAL)
        .fontColor('#FFFFFF')
        .borderRadius(Tokens.RADIUS_PILL)
        .enabled(!this.uploading)
        .onClick(() => {
          this.pickAndUpload();
        })

      if (this.uploading) {
        Column() {
          Row() {
            Text(this.uploadName)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.TEXT_SECONDARY)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.uploadPercent + '%')
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
          }
          .width('100%')
          Progress({ value: this.uploadPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .margin({ top: 6 })
            .color(Tokens.MIST_TEAL)
            .backgroundColor(Tokens.DIVIDER)
          Text(this.uploadStateText)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 4 })
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  fileRow(file: CloudSpaceFile) {
    Row() {
      Text(CloudSpaceLogic.fileKindGlyph(CloudSpaceLogic.fileKind(file.mimeType, file.name)))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Tokens.SLATE_BLUE)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .backgroundColor(Tokens.TINT_BLUE)
        .borderRadius(12)

      Column() {
        Text(file.name)
          .fontSize(Tokens.F_BODY)
          .fontColor(Tokens.TEXT_PRIMARY)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.fileMeta(file))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 3 })
          .width('100%')
        if (this.downloadingId === file.id) {
          Text(this.uploadStateText.length > 0 ? this.uploadStateText : '下载中…')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.MIST_TEAL)
            .margin({ top: 3 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 10 })

      Column() {
        Text('下载')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.MIST_TEAL)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.downloadFile(file);
          })
        Text('删除')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.DANGER)
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => {
            this.confirmDelete(file);
          })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .backgroundColor(Tokens.CARD)
  }

  @Builder
  fileList() {
    Column() {
      Row() {
        Text('文件')
          .fontSize(Tokens.F_LABEL)
          .fontWeight(FontWeight.Bold)
          .fontColor(Tokens.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.files.length + ' 个')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
      }
      .width('100%')
      .margin({ bottom: 4 })

      if (this.loading) {
        Text('正在连接云空间…')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else if (this.files.length === 0) {
        Text(this.connected ? '还没有文件：上传后同账号设备立即可见' : '云空间未连接：点「刷新」重试')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .width('100%')
          .padding({ top: 12, bottom: 12 })
      } else {
        ForEach(this.files, (file: CloudSpaceFile) => {
          this.fileRow(file)
        }, (file: CloudSpaceFile) => file.id)
      }

      if (this.expiredCount > 0) {
        Text(CloudSpaceLogic.expiredHint(this.expiredCount))
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.WARM_SAND)
          .width('100%')
          .margin({ top: 6 })
      }

      Button('清空云空间')
        .width('100%')
        .height(40)
        .margin({ top: 12 })
        .backgroundColor(Tokens.BG)
        .fontColor(Tokens.DANGER)
        .fontSize(Tokens.F_LABEL)
        .borderRadius(Tokens.RADIUS_PILL)
        .onClick(() => {
          this.confirmClear();
        })
    }
    .width('100%')
    .padding(16)
    .margin({ top: 12 })
    .backgroundColor(Tokens.CARD)
    .borderRadius(Tokens.RADIUS_CARD)
  }

  build() {
    Column() {
      this.header()
      Scroll() {
        Column() {
          this.uploadBar()
          this.fileList()

          if (this.statusMsg.length > 0) {
            Text(this.statusMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.MIST_TEAL)
              .width('100%')
              .margin({ top: 10 })
          }
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg)
              .fontSize(Tokens.F_CAPTION)
              .fontColor(Tokens.WARM_SAND)
              .width('100%')
              .margin({ top: 10 })
          }

          Text('班级 token 只在请求头中传输；文件只临时中转，不做持久化/病毒扫描，请勿存放重要资料。')
            .fontSize(Tokens.F_CAPTION)
            .fontColor(Tokens.TEXT_TERTIARY)
            .width('100%')
            .margin({ top: 12, bottom: 24 })
        }
        .width('100%')
        .constraintSize({ maxWidth: this.contentMax() })
        .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Tokens.BG)
    .padding({ top: Breakpoints.BREATH_TOP })
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const next: number = Number(newArea.width);
      if (Math.abs(next - this.layoutWidth) > 1) {
        this.layoutWidth = next;
      }
    })
  }
}
