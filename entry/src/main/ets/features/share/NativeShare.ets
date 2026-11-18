import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppGlobal } from '../../app/AppGlobal';
import { ImageSaver } from '../../data/export/ImageSaver';
import { Log } from '../../common/Log';

const TAG: string = 'NativeShare';

/** 拉起系统分享面板的结果（面板成功呈现即视为 ok）。 */
export class ShareResult {
  ok: boolean;
  message: string;

  constructor(ok: boolean, message: string) {
    this.ok = ok;
    this.message = message;
  }
}

/**
 * 系统分享（Share Kit）统一入口。
 *
 * - 文本 / 链接走 DEFAULT 卡片预览，图片 / 文件走 DETAIL 大图预览；
 * - 缩略图、分享方式区、系统操作区均由系统分享面板提供，应用不自定义；
 * - 分享面板内的「复制」等系统操作由系统按内容类型自动补全。
 */
export class NativeShare {
  private static async show(data: systemShare.SharedData,
    previewMode: systemShare.SharePreviewMode,
    selectionMode: systemShare.SelectionMode): Promise<ShareResult> {
    const context = AppGlobal.context;
    if (context === undefined) {
      return new ShareResult(false, '分享服务暂不可用，请稍后重试');
    }
    try {
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const options: systemShare.ShareControllerOptions = {
        previewMode: previewMode,
        selectionMode: selectionMode
      };
      await controller.show(context, options);
      return new ShareResult(true, '已打开分享面板');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, 'show fail code=' + err.code + ' msg=' + err.message);
      return new ShareResult(false, '无法打开分享面板（' + err.code + '）');
    }
  }

  /** 分享纯文本：系统操作区自动提供「复制」。 */
  static async shareText(title: string, text: string, description: string = ''): Promise<ShareResult> {
    const body: string = text.trim();
    if (body.length === 0) {
      return new ShareResult(false, '没有可分享的内容');
    }
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.TEXT,
      content: body,
      title: title,
      description: description
    };
    return NativeShare.show(new systemShare.SharedData(record),
      systemShare.SharePreviewMode.DEFAULT, systemShare.SelectionMode.SINGLE);
  }

  /** 分享网页 / App Linking 链接（内容可直达浏览器或应用）。 */
  static async shareLink(url: string, title: string, description: string = ''): Promise<ShareResult> {
    if (url.trim().length === 0) {
      return new ShareResult(false, '链接为空，无法分享');
    }
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.HYPERLINK,
      content: url,
      title: title,
      description: description
    };
    return NativeShare.show(new systemShare.SharedData(record),
      systemShare.SharePreviewMode.DEFAULT, systemShare.SelectionMode.SINGLE);
  }

  /** 分享单张图片（沙箱路径 → 应用文件 URI），大卡预览。 */
  static async shareImage(path: string, title: string, description: string = ''): Promise<ShareResult> {
    return NativeShare.shareFiles([path], title, description, true);
  }

  /**
   * 把任意 @Builder 离屏渲染成 PNG，再走系统图片分享（大卡预览）。
   * 统一分享出口：所有业务内容都先转成分享卡图片，不在分享面板里放纯文本。
   */
  static async shareCard(ui: UIContext, builder: CustomBuilder, fileName: string, title: string,
    description: string = ''): Promise<ShareResult> {
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      pixelMap = await ui.getComponentSnapshot().createFromBuilder(builder, 300, false, {
        scale: 2,
        waitUntilRenderFinished: true
      });
      const packer: image.ImagePacker = image.createImagePacker();
      let data: ArrayBuffer;
      try {
        data = await packer.packToData(pixelMap, { format: 'image/png', quality: 100 });
      } finally {
        await packer.release();
      }
      const safeName: string = fileName.length > 0 ? fileName : ('share_' + Date.now() + '.png');
      const path: string = await ImageSaver.writeToAppFile(data, safeName);
      if (path.length === 0) {
        return new ShareResult(false, '生成分享图片失败');
      }
      return await NativeShare.shareImage(path, title, description);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, 'shareCard fail code=' + err.code + ' msg=' + err.message);
      return new ShareResult(false, '生成分享图片失败（' + err.code + '）');
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
    }
  }

  /**
   * 分享图片 / 文件（可多张）。
   * 多文件使用 BATCH 模式，一条记录对应一个系统预览缩略图。
   */
  static async shareFiles(paths: string[], title: string, description: string = '',
    imageOnly: boolean = false): Promise<ShareResult> {
    const valid: string[] = [];
    for (let i = 0; i < paths.length; i++) {
      if (paths[i].trim().length > 0) {
        valid.push(paths[i]);
      }
    }
    if (valid.length === 0) {
      return new ShareResult(false, '没有可分享的文件');
    }
    try {
      const first: systemShare.SharedRecord = NativeShare.fileRecord(valid[0], title, description, imageOnly);
      const data: systemShare.SharedData = new systemShare.SharedData(first);
      for (let i = 1; i < valid.length; i++) {
        data.addRecord(NativeShare.fileRecord(valid[i], title, description, imageOnly));
      }
      return NativeShare.show(data,
        imageOnly ? systemShare.SharePreviewMode.DETAIL : systemShare.SharePreviewMode.DEFAULT,
        valid.length > 1 ? systemShare.SelectionMode.BATCH : systemShare.SelectionMode.SINGLE);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, 'build file share fail code=' + err.code + ' msg=' + err.message);
      return new ShareResult(false, '分享内容构造失败');
    }
  }

  private static fileRecord(path: string, title: string, description: string,
    imageOnly: boolean): systemShare.SharedRecord {
    const dot: number = path.lastIndexOf('.');
    const ext: string = dot >= 0 ? path.substring(dot) : (imageOnly ? '.png' : '');
    const utdType: string = ext.length > 0
      ? utd.getUniformDataTypeByFilenameExtension(ext, imageOnly ? utd.UniformDataType.IMAGE : utd.UniformDataType.FILE)
      : (imageOnly ? utd.UniformDataType.IMAGE : utd.UniformDataType.FILE);
    const uri: string = fileUri.getUriFromPath(path);
    const record: systemShare.SharedRecord = {
      utd: utdType,
      uri: uri,
      title: title,
      description: description
    };
    if (imageOnly) {
      record.thumbnailUri = uri;
    }
    return record;
  }
}
