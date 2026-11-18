/** 随机数引擎抽象（可注入 seed，保证单测可复现）。 */
export interface DrawRandom {
  /** 返回 `0..bound-1` 的随机整数；`bound <= 0` 时返回 0。 */
  nextInt(bound: number): number;
}

/** 可复现实现（mulberry32）：同 seed 同序列，与平台随机源解耦。 */
export class SeededDrawRandom implements DrawRandom {
  private state: number = 0;

  constructor(seed: number) {
    this.state = (seed >>> 0);
  }

  nextInt(bound: number): number {
    if (bound <= 0) {
      return 0;
    }
    this.state = (this.state + 0x6D2B79F5) >>> 0;
    let t: number = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t = (t ^ (t + Math.imul(t ^ (t >>> 7), t | 61))) >>> 0;
    const unit: number = ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    return Math.floor(unit * bound);
  }
}

/** 默认引擎：时间种子（每次抽签不可复现，与网页行为一致）。 */
export function defaultDrawRandom(): DrawRandom {
  return new SeededDrawRandom(Date.now() % 2147483647);
}

/** Fisher-Yates 洗牌（与网页实现同算法）；返回新数组。 */
export function shuffledInts(size: number, random: DrawRandom): number[] {
  const list: number[] = [];
  for (let i = 0; i < size; i++) {
    list.push(i);
  }
  for (let i = list.length - 1; i >= 1; i--) {
    const j: number = random.nextInt(i + 1);
    const tmp: number = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}

/** 对任意数组做 Fisher-Yates 洗牌。 */
export function shuffled<T>(items: T[], random: DrawRandom): T[] {
  const list: T[] = items.slice(0);
  for (let i = list.length - 1; i >= 1; i--) {
    const j: number = random.nextInt(i + 1);
    const tmp: T = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
