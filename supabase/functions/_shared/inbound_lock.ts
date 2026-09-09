export type LockSession = {
  lock(key: string): Promise<void>;
  unlock(key: string): Promise<void>;
};

type Held = { session: number; count: number; waiters: Array<() => void> };

/** Models PostgreSQL session-level advisory locks (reentrant on the same session). */
export class FakeAdvisoryBackend {
  private nextSession = 1;
  private readonly held = new Map<string, Held>();

  newSession(): LockSession {
    const session = this.nextSession++;
    return {
      lock: (key) => this.lock(session, key),
      unlock: async (key) => this.unlock(session, key),
    };
  }

  private lock(session: number, key: string): Promise<void> {
    const current = this.held.get(key);
    if (!current) {
      this.held.set(key, { session, count: 1, waiters: [] });
      return Promise.resolve();
    }
    if (current.session === session) {
      current.count += 1;
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      current.waiters.push(() => {
        this.held.set(key, { session, count: 1, waiters: [] });
        resolve();
      });
    });
  }

  private unlock(session: number, key: string): void {
    const current = this.held.get(key);
    if (!current || current.session !== session) {
      return;
    }
    current.count -= 1;
    if (current.count > 0) {
      return;
    }
    const next = current.waiters.shift();
    if (next) {
      next();
      return;
    }
    this.held.delete(key);
  }
}

export async function runWithLock<T>(
  session: LockSession,
  key: string,
  fn: () => Promise<T>,
): Promise<T> {
  await session.lock(key);
  try {
    return await fn();
  } finally {
    await session.unlock(key);
  }
}
