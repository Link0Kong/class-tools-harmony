import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { Log } from '../../common/Log';

const TAG: string = 'VoteImage';
const MAX_CHARS: number = 150000;
const MAX_EDGE: number = 640;

/** 投票选项配图：相册选择 → 缩放到长边 ≤640 → JPEG → data URL（≤150000 字符）。 */
export class VoteImage {
  /** 返回 data URL；空串 = 取消/失败。 */
  static async pick(): Promise<string> {
    let uri: string = '';
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.maxSelectNumber = 1;
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        return '';
      }
      uri = result.photoUris[0];
    } catch (e) {
      Log.w(TAG, '打开相册失败');
      return '';
    }
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const source: image.ImageSource = image.createImageSource(file.fd);
      const info: image.ImageInfo = await source.getImageInfo();
      const width: number = info.size.width;
      const height: number = info.size.height;
      const scale: number = Math.min(1, MAX_EDGE / Math.max(width, height));
      const decode: image.DecodingOptions = {
        desiredSize: {
          width: Math.max(1, Math.round(width * scale)),
          height: Math.max(1, Math.round(height * scale))
        }
      };
      const pixelMap: image.PixelMap = await source.createPixelMap(decode);
      const packer: image.ImagePacker = image.createImagePacker();
      const helper: util.Base64Helper = new util.Base64Helper();
      const qualities: number[] = [72, 55, 40, 28];
      for (let i = 0; i < qualities.length; i++) {
        const pack: image.PackingOption = { format: 'image/jpeg', quality: qualities[i] };
        const buffer: ArrayBuffer = await packer.packToData(pixelMap, pack);
        const base64: string = helper.encodeToStringSync(new Uint8Array(buffer));
        if (base64.length <= MAX_CHARS) {
          await pixelMap.release();
          return 'data:image/jpeg;base64,' + base64;
        }
      }
      await pixelMap.release();
      return '';
    } catch (e) {
      Log.w(TAG, '压缩图片失败');
      return '';
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 忽略
        }
      }
    }
  }

  static dataUrlOf(pollOptionImage: string): string {
    if (pollOptionImage.startsWith('data:image/')) {
      return pollOptionImage;
    }
    return '';
  }
}
