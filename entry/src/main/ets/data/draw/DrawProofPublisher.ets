import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Api } from '../net/Api';
import { Blob, JsonBlob } from '../sync/JsonBlob';
import { DrawEntry, DrawPoolSource, DrawReceipt, DrawResult } from '../../features/draw/DrawModels';
import { DrawValidator } from '../../features/draw/DrawValidator';
import { SeededDrawRandom } from '../../features/draw/DrawRandom';

export class ProofEvent {
  kind: string;
  n: number | null;
  added: number | null;
  constructor(kind: string, n: number | null = null, added: number | null = null) {
    this.kind = kind;
    this.n = n;
    this.added = added;
  }

  matches(event: Blob | undefined): boolean {
    return !!event && event['kind'] === this.kind && (event['n'] ?? null) === this.n &&
      (event['added'] ?? null) === this.added && !event['note'];
  }
}

export function drawHashMatches(canon: string, hash: string): boolean {
  if (!canon || !new RegExp('^[a-f0-9]{64}$').test(hash)) return false;
  const md = cryptoFramework.createMd('SHA256');
  md.updateSync({ data: new util.TextEncoder().encodeInto(canon) });
  return Array.from(md.digestSync().data).map((b: number) => b.toString(16).padStart(2, '0')).join('') === hash;
}

/** One queue per draw ID. A retry reuses the ID and reconciles prior append acknowledgements. */
export class DrawProofRound {
  id: string = 'd' + util.generateRandomUUID(true).replace(new RegExp('-', 'g'), '').slice(0, 28);
  seed: string = util.generateRandomUUID(true).replace(new RegExp('-', 'g'), '').slice(-16);
  events: ProofEvent[] = [];
  private queue: Promise<DrawReceipt | undefined> = Promise.resolve(undefined);
  private initial: Blob | undefined;
  private owner: string;

  constructor(owner: string) {
    this.owner = owner;
  }

  random(): SeededDrawRandom {
    return new SeededDrawRandom(parseInt(this.seed.slice(0, 8), 16));
  }

  start(result: DrawResult): void {
    const cfg = result.config;
    const pool = result.pool.map((e: DrawEntry) => e.number);
    const excluded = Array.from(DrawValidator.parseExcluded(cfg.excludedText).numbers).sort((a: number, b: number) => a - b);
    const params: Blob = { 'range': [cfg.start, cfg.end], 'count': cfg.count, 'dup': cfg.allowDuplicates,
      'sort': cfg.sort, 'excl': excluded, 'rosterN': cfg.poolSource === DrawPoolSource.ROSTER ? pool.length : 0, 'namesN': 0 };
    this.initial = { 'p_id': this.id, 'p_seed': this.seed, 'p_algo': 'draw-v1', 'p_pool': pool,
      'p_result': result.original.slice(), 'p_labels': [], 'p_params': params };
  }

  publish(api: Api, current: () => string): Promise<DrawReceipt | undefined> {
    const events = this.events.slice();
    this.queue = this.queue.then(() => this.send(api, current, events)).catch(() => undefined);
    return this.queue;
  }

  private async send(api: Api, current: () => string, events: ProofEvent[]): Promise<DrawReceipt | undefined> {
    if (!this.initial || !this.owner || current() !== this.owner) return undefined;
    const response = await api.post('rpc/draw_record_create', JSON.stringify(this.initial), '', true);
    const reply = response.ok ? JsonBlob.parse(response.value) : undefined;
    const rec = reply?.['ok'] === true ? JsonBlob.asBlob(reply['record']) : undefined;
    if (!rec || rec['id'] !== this.id || rec['seed'] !== this.seed ||
      !JsonBlob.deepEqual(rec['result'], this.initial['p_result'])) return undefined;
    const canon = JsonBlob.asString(rec['canon'], '');
    const hash = JsonBlob.asString(rec['hash'], '');
    if (!drawHashMatches(canon, hash)) return undefined;
    const prior = JsonBlob.asArray(rec['events']);
    if (!prior || prior.length > events.length) return undefined;
    for (let i = 0; i < events.length; i++) {
      const ev = events[i];
      if (i < prior.length) {
        if (!ev.matches(JsonBlob.asBlob(prior[i]))) return undefined;
      } else {
        if (current() !== this.owner) return undefined;
        const body: Blob = { 'p_id': this.id, 'p_kind': ev.kind, 'p_n': ev.n, 'p_added': ev.added, 'p_note': '' };
        const sent = await api.post('rpc/draw_event_append', JSON.stringify(body), '', true);
        const ack = sent.ok ? JsonBlob.parse(sent.value) : undefined;
        if (!ack || ack['ok'] !== true || !ev.matches(JsonBlob.asBlob(ack['event']))) return undefined;
      }
    }
    const receipt = new DrawReceipt();
    receipt.id = this.id;
    receipt.hash = hash;
    receipt.sequence = JsonBlob.asNumber(rec['seq_day'], 0);
    receipt.total = JsonBlob.asNumber(rec['today_count'], 0);
    receipt.at = JsonBlob.asNumber(rec['at'], 0);
    return receipt.at > 0 && receipt.sequence > 0 && receipt.total >= receipt.sequence && current() === this.owner
      ? receipt : undefined;
  }
}
