import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ExportCardSpec } from '../../features/export/ExportCard';
import { ImageSaver, SaveResult } from '../../data/export/ImageSaver';
import { NativeShare, ShareResult } from '../../features/share/NativeShare';
import { Tokens } from '../theme/Tokens';
import { Motion } from '../theme/Motion';
import { Immersive } from '../theme/Immersive';
import { ExportCardView } from '../components/ExportCardView';
import { Log } from '../../common/Log';

const TAG: string = 'ExportPreview';

/**
 * 导出预览：展示 760 宽导出卡（可滚动查看），截图为 PNG 后保存沙箱 + 相册。
 *
 * 截图：`UIContext.getComponentSnapshot().get('exportCard', {scale:2})`；
 * 相册：`photoAccessHelper.showAssetsCreationDialog`（系统确认框，无需写媒体权限）。
 */
@Component
export struct ExportPreview {
  spec: ExportCardSpec = new ExportCardSpec();
  onClose: () => void = () => {
  };

  @State private status: string = '';
  @State private saving: boolean = false;
  @State private sharing: boolean = false;
  @State private entered: boolean = false;

  aboutToAppear(): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: Motion.NORMAL, curve: Motion.ease() }, () => {
        this.entered = true;
      });
    }, 20);
  }

  private async capture(): Promise<ArrayBuffer | undefined> {
    try {
      const pixelMap: image.PixelMap = await this.getUIContext()
        .getComponentSnapshot()
        .get('exportCard', { scale: 2 });
      const packer: image.ImagePacker = image.createImagePacker();
      try {
        const data: ArrayBuffer = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
        return data;
      } finally {
        await packer.release();
        await pixelMap.release();
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, '截图失败 code=' + err.code + ' msg=' + err.message);
      return undefined;
    }
  }

  /** 仅保存到应用沙箱（不弹相册确认；用于系统对话框无响应时兜底）。 */
  private async saveFileOnly(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.status = '正在生成图片…';
    try {
      const data: ArrayBuffer | undefined = await this.capture();
      if (data === undefined) {
        this.status = '生成图片失败，请重试';
        return;
      }
      const path: string = await ImageSaver.writeToAppFile(data, this.spec.fileName);
      this.status = path.length > 0 ? '已保存到应用文件：' + this.spec.fileName : '写入文件失败';
    } finally {
      this.saving = false;
    }
  }

  private async save(): Promise<void> {
    if (this.saving) {
      return;
    }
    this.saving = true;
    this.status = '正在生成图片…';
    try {
      const data: ArrayBuffer | undefined = await this.capture();
      if (data === undefined) {
        this.status = '生成图片失败，请重试';
        return;
      }
      const path: string = await ImageSaver.writeToAppFile(data, this.spec.fileName);
      if (path.length === 0) {
        this.status = '写入文件失败';
        return;
      }
      this.status = '已生成，正在打开相册确认…';
      const result: SaveResult | undefined = await ExportPreview.withTimeout(
        ImageSaver.saveToGallery(path, this.spec.fileName), 15000);
      if (result === undefined) {
        this.status = '相册确认超时：图片已保存到应用文件，可点「仅保存文件」重试';
        return;
      }
      this.status = result.message;
    } finally {
      this.saving = false;
    }
  }

  /** 生成图片后直接拉起系统分享面板（大卡预览，系统操作区含复制/保存等）。 */
  private async share(): Promise<void> {
    if (this.saving || this.sharing) {
      return;
    }
    this.sharing = true;
    this.status = '正在生成图片…';
    try {
      const data: ArrayBuffer | undefined = await this.capture();
      if (data === undefined) {
        this.status = '生成图片失败，请重试';
        return;
      }
      const path: string = await ImageSaver.writeToAppFile(data, this.spec.fileName);
      if (path.length === 0) {
        this.status = '写入文件失败';
        return;
      }
      const result: ShareResult = await NativeShare.shareImage(path, this.spec.title,
        this.spec.subtitle.length > 0 ? this.spec.subtitle : this.spec.footer);
      this.status = result.message;
    } finally {
      this.sharing = false;
    }
  }

  /** Promise 超时保护（相册确认框偶发不弹出时避免 UI 卡死）。 */
  private static async withTimeout<T>(task: Promise<T>, ms: number): Promise<T | undefined> {
    let timer: number = -1;
    const timeout: Promise<undefined> = new Promise<undefined>((resolve: (value: undefined) => void) => {
      timer = setTimeout(() => {
        resolve(undefined);
      }, ms);
    });
    const result: T | undefined = await Promise.race<T | undefined>([task, timeout]);
    if (timer >= 0) {
      clearTimeout(timer);
    }
    return result;
  }

  build() {
    Column() {
      Row() {
        Text('关闭')
          .fontSize(Tokens.F_LABEL)
          .fontColor(Tokens.TEXT_SECONDARY)
          .height(44)
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.onClose();
          })
        Blank()
        Text('导出图片')
          .fontSize(Tokens.F_HEADING)
          .fontWeight(FontWeight.Medium)
          .fontColor(Tokens.TEXT_PRIMARY)
        Blank()
        Text('')
          .width(56)
      }
      .width('100%')
      .height(56)

      Scroll() {
        Scroll() {
          ExportCardView({ spec: this.spec })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)

      Column() {
        if (this.status.length > 0) {
          Text(this.status)
            .fontSize(Tokens.F_CAPTION)
            .fontColor(this.saving || this.sharing ? Tokens.TEXT_SECONDARY : Tokens.MIST_TEAL)
            .margin({ bottom: 8 })
        }
        Row({ space: 8 }) {
          Button(this.saving ? '保存中…' : '保存到相册')
            .layoutWeight(2)
            .height(48)
            .backgroundColor(this.saving || this.sharing ? Tokens.tint(Tokens.MIST_TEAL, 0.5) : Tokens.MIST_TEAL)
            .fontColor('#FFFFFF')
            .borderRadius(Tokens.RADIUS_PILL)
            .enabled(!this.saving && !this.sharing)
            .onClick(() => {
              this.save();
            })
          Button(this.sharing ? '分享中…' : '分享')
            .layoutWeight(1)
            .height(48)
            .backgroundColor(this.saving || this.sharing ? Tokens.tint(Tokens.SLATE_BLUE, 0.5) : Tokens.SLATE_BLUE)
            .fontColor('#FFFFFF')
            .borderRadius(Tokens.RADIUS_PILL)
            .enabled(!this.saving && !this.sharing)
            .onClick(() => {
              this.share();
            })
          Button('更多')
            .layoutWeight(1)
            .height(48)
            .backgroundColor(Tokens.CONTROL)
            .border({ width: 0.5, color: Tokens.CARD_EDGE })
            .fontColor(Tokens.TEXT_SECONDARY)
            .borderRadius(Tokens.RADIUS_PILL)
            .enabled(!this.saving && !this.sharing)
            .bindMenu([
              {
                value: '仅保存文件',
                action: () => {
                  this.saveFileOnly();
                }
              }
            ], { systemMaterial: Immersive.dialogMaterial() })
        }
        .width('100%')
        Text('图片已同时保存到应用文件，可在无相册权限时兜底')
          .fontSize(Tokens.F_CAPTION)
          .fontColor(Tokens.TEXT_TERTIARY)
          .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: Tokens.PAGE_PADDING, right: Tokens.PAGE_PADDING, bottom: 18, top: 8 })
      .backgroundColor(Tokens.ACTION_BAR)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: Tokens.CARD_EDGE })
      .borderRadius({ topLeft: Tokens.RADIUS_FLOAT, topRight: Tokens.RADIUS_FLOAT })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F2F7F8F8')
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 26 })
  }
}
