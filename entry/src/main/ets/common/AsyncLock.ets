/** 极简异步互斥（替代 Kotlin Mutex；ArkTS 无协程）。 */
export class AsyncLock {
  private tail: Promise<void> = Promise.resolve();

  async run<T>(task: () => Promise<T>): Promise<T> {
    const previous: Promise<void> = this.tail;
    let release: () => void = () => {
    };
    this.tail = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      return await task();
    } finally {
      release();
    }
  }
}
