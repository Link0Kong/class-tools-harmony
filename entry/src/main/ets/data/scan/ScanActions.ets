import { http } from '@kit.NetworkKit';
import { Services } from '../../app/Services';
import { DrawConfig, DrawEntry } from '../../features/draw/DrawModels';
import { DrawEngine } from '../../features/draw/DrawEngine';
import { SeededDrawRandom } from '../../features/draw/DrawRandom';
import { drawHashMatches } from '../draw/DrawProofPublisher';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { field, numberField } from '../tasks/TaskModels';
import { ScanPayload } from './ScanPayload';

export class ScanReply {
  ok: boolean = false;
  text: string = '';
}

export class ScanActions {
  static async login(code: ScanPayload, allow: boolean): Promise<ScanReply> {
    const reply = new ScanReply();
    if (code.kind !== 'login' || !/^[0-9a-f]{32}$/.test(code.ticket) || !Services.currentToken) {
      reply.text = '请重新验证班级身份并扫描电脑上的登录码';
      return reply;
    }
    const body: Blob = { 't': code.ticket, 'p': code.harmony ? 'harmony' : 'any', 'via': 'app' };
    const endpoint = 'https://tool.furina.fun/account/qr/' + (allow ? 'authorize' : 'deny');
    const request = http.createHttp();
    try {
      const response = await request.request(endpoint, { method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'X-Class-Token': Services.currentToken },
        extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 10000, maxRedirects: 0,
        usingCache: false, expectDataType: http.HttpDataType.STRING });
      const doc = typeof response.result === 'string' ? JsonBlob.parse(response.result) : undefined;
      reply.ok = response.responseCode === 200 && doc?.['ok'] === true;
      if (reply.ok) reply.text = allow ? '已确认登录，请返回电脑继续' : '已取消本次网页登录';
      else if (response.responseCode === 401 || response.responseCode === 403) reply.text = '班级身份已失效，请重新登录';
      else if (response.responseCode === 429) reply.text = '请求过于频繁，请稍后重试';
      else if (doc?.['code'] === 'ticket_expired') reply.text = '二维码已过期，请刷新电脑上的登录码';
      else reply.text = '无法确认这次网页登录，请重试或重新扫码';
    } catch (_) { reply.text = '扫码服务连接失败，请检查网络后重试'; }
    finally { request.destroy(); }
    return reply;
  }

  static async verify(id: string): Promise<ScanReply> {
    const reply = new ScanReply();
    if (!/^d[0-9a-z]{8,31}$/.test(id)) { reply.text = '无效的存证编号'; return reply; }
    try {
      const body: Blob = { 'p_id': id };
      const result = await Services.api.post('rpc/draw_record_get', JSON.stringify(body));
      if (!result.ok) { reply.text = '无法读取抽签存证，请稍后重试'; return reply; }
      const doc = JsonBlob.parse(result.value);
      const record = doc?.['ok'] === true ? JsonBlob.asBlob(doc['record']) : undefined;
      if (!record || record['id'] !== id) { reply.text = '这条存证不存在或当前身份不可查看'; return reply; }
      const canon = field(record, 'canon');
      const parts = canon.split('\n');
      const params = JsonBlob.asBlob(record['params']);
      const pool = JsonBlob.asArray(record['pool']);
      const numbers = JsonBlob.asArray(record['result']);
      const seed = field(record, 'seed');
      const count = params ? numberField(params, 'count') : 0;
      if (!params || !pool || !numbers || count < 1 || count > 1000 || !pool.length || pool.length > 1000 ||
        !Number.isInteger(count) || !/^[a-f0-9]{16}$/.test(seed) || record['algo'] !== 'draw-v1' ||
        parts.length !== 12 || parts[0] !== 'v1' || parts[1] !== id || parts[5] !== 'draw-v1' || parts[6] !== seed ||
        !drawHashMatches(canon, field(record, 'hash')) ||
        !JsonBlob.deepEqual(JsonBlob.parse(parts[8]), params) ||
        !JsonBlob.deepEqual(JSON.parse(parts[9]) as Object, pool) || !JsonBlob.deepEqual(JSON.parse(parts[10]) as Object, numbers)) {
        reply.text = '存证内容或哈希未通过核验'; return reply;
      }
      const cfg = new DrawConfig();
      cfg.count = count;
      cfg.allowDuplicates = params['dup'] === true;
      const candidates = pool.map((n: Object) => new DrawEntry(JsonBlob.asNumber(n, -1)));
      if (!cfg.allowDuplicates && cfg.count > candidates.length) { reply.text = '存证抽取数量异常'; return reply; }
      const replay = DrawEngine.pick(cfg, candidates, new SeededDrawRandom(parseInt(seed.slice(0, 8), 16)));
      if (!JsonBlob.deepEqual(replay.map((entry: DrawEntry) => entry.number), numbers)) {
        reply.text = '抽签结果与种子复算不一致'; return reply;
      }
      reply.ok = true;
      reply.text = '原始结果哈希与种子复算通过\n' + numbers.join('、') + '\n' + field(record, 'day') +
        ' 第 ' + numberField(record, 'seq_day') + ' 次抽签 · 当天共 ' + numberField(record, 'today_count') +
        ' 次\n后续操作 ' + numberField(record, 'event_count') + ' 次';
    } catch (_) { reply.text = '无法核验这条抽签记录，请稍后重试'; }
    return reply;
  }
}
