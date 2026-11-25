import { Services } from '../../app/Services';
import { NotificationDelivery } from '../notify/NotificationDelivery';
import { LiveActivity } from '../notify/LiveActivity';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { PptUploadPlanner } from '../../features/ppt/PptUploadPlanner';
import { PptUploadRepository } from './PptUploadRepository';
import { Log } from '../../common/Log';

const TAG: string = 'PptUploader';

/** 演示文件分片上传（512 KiB/片，顺序 ≤4 并行退化为顺序，稳健优先）。 */
export class PptUploader {
  private repo: PptUploadRepository;
  private ownerSid: string;
  private ownerName: string;

  constructor(repo: PptUploadRepository, ownerSid: string, ownerName: string) {
    this.repo = repo;
    this.ownerSid = ownerSid;
    this.ownerName = ownerName;
  }

  /** 返回空串 = 成功；否则为错误文案。进度回调 (done, total)。 */
  async upload(uri: string, name: string, onProgress: (done: number, total: number) => void): Promise<string> {
    let activityId: number = 0;
    let queuedForConversion: boolean = false;
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const size: number = fs.statSync(file.fd).size;
      const invalid: string = PptUploadPlanner.validate(name, size);
      if (invalid.length > 0) {
        return invalid;
      }
      if (this.ownerSid !== Services.currentSid) return '登录账号已切换，上传已停止';
      const deckId: string = PptUploadPlanner.deckId(Date.now(), size + name.length);
      activityId = NotificationDelivery.id('ppt:' + this.ownerSid + ':' + deckId);
      LiveActivity.upload(activityId, this.ownerSid, name, -1, '准备文件');
      const created: boolean = await this.repo.createDeck(deckId,
        PptUploadPlanner.titleOf(name), size, PptUploadPlanner.extOf(name), name,
        this.ownerSid, this.ownerName, Date.now());
      if (!created) {
        return '创建上传记录失败（登录或权限问题）';
      }
      const total: number = PptUploadPlanner.chunkCount(size);
      LiveActivity.upload(activityId, this.ownerSid, name, 0, '上传中');
      onProgress(0, total);
      const helper: util.Base64Helper = new util.Base64Helper();
      for (let i = 0; i < total; i++) {
        if (this.ownerSid !== Services.currentSid) return '登录账号已切换，上传已停止';
        const range: number[] = PptUploadPlanner.chunkRange(i, size);
        const length: number = range[1];
        if (length <= 0) {
          continue;
        }
        const buffer: ArrayBuffer = new ArrayBuffer(length);
        const read: number = fs.readSync(file.fd, buffer, { offset: range[0], length: length });
        if (read !== length) {
          return '读取文件失败（分片 ' + i + '）';
        }
        const bytes: Uint8Array = new Uint8Array(buffer.slice(0, read));
        const base64: string = helper.encodeToStringSync(bytes);
        const ok: boolean = await this.repo.putChunk(deckId, this.ownerSid, i, base64, Date.now());
        if (!ok) {
          return '分片上传失败（' + i + '/' + total + '）';
        }
        onProgress(i + 1, total);
        LiveActivity.upload(activityId, this.ownerSid, name, (i + 1) * 100 / total, '上传中');
      }
      if (this.ownerSid !== Services.currentSid) return '登录账号已切换，上传已停止';
      LiveActivity.upload(activityId, this.ownerSid, name, -1, '提交转换');
      const queued: boolean = await this.repo.queue(deckId, total, size, Date.now());
      if (!queued) {
        return '上传完成但排队失败，请重试';
      }
      queuedForConversion = true;
      LiveActivity.followConversion(this.ownerSid, deckId, name, activityId);
      return '';
    } catch (e) {
      Log.e(TAG, '上传异常：' + JSON.stringify(e));
      return '上传异常，请稍后重试';
    } finally {
      if (activityId && !queuedForConversion) {
        await LiveActivity.finishUpload(activityId, this.ownerSid, name, '上传失败');
      }
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e) {
          // 忽略关闭失败
        }
      }
    }
  }
}
