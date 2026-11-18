import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppGlobal } from '../../app/AppGlobal';
import { Log } from '../../common/Log';

const TAG: string = 'ImageSaver';

export class SaveResult {
  ok: boolean;
  message: string;
  /** 相册 uri（保存到相册成功时）。 */
  uri: string;
  /** 应用沙箱路径（总是有）。 */
  path: string;

  constructor(ok: boolean, message: string, uri: string, path: string) {
    this.ok = ok;
    this.message = message;
    this.uri = uri;
    this.path = path;
  }
}

/**
 * 导出图片落盘：
 * 1. 先写应用沙箱 `filesDir/export/<文件名>`（一定成功，作为兜底）；
 * 2. 再走 `photoAccessHelper.showAssetsCreationDialog` 让用户确认保存到相册（无需 WRITE_IMAGEVIDEO 权限）。
 */
export class ImageSaver {
  static async writeToAppFile(data: ArrayBuffer, fileName: string): Promise<string> {
    const ctx = AppGlobal.context;
    if (ctx === undefined) {
      return '';
    }
    try {
      const dir: string = ctx.filesDir + '/export';
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const path: string = dir + '/' + fileName;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
      return path;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, '写入沙箱失败 code=' + err.code);
      return '';
    }
  }

  static async saveToGallery(path: string, fileName: string): Promise<SaveResult> {
    const ctx = AppGlobal.context;
    if (ctx === undefined || path.length === 0) {
      return new SaveResult(false, '无应用上下文', '', path);
    }
    try {
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const title: string = fileName.replace(new RegExp('\\.png$'), '');
      const srcUri: string = fileUri.getUriFromPath(path);
      const configs: photoAccessHelper.PhotoCreationConfig[] = [{
        title: title,
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE
      }];
      const uris: string[] = await helper.showAssetsCreationDialog([srcUri], configs);
      if (uris.length === 0) {
        return new SaveResult(false, '已取消保存', '', path);
      }
      // 把沙箱内容写入相册资产
      const src = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(src.fd).size;
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(src.fd, buffer);
      fs.closeSync(src);

      const dst = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
      fs.writeSync(dst.fd, buffer);
      fs.closeSync(dst);
      return new SaveResult(true, '已保存到相册', uris[0], path);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(TAG, '保存相册失败 code=' + err.code + ' msg=' + err.message);
      return new SaveResult(false, '保存失败：' + err.message, '', path);
    }
  }
}
