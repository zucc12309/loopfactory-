/**
 * Deterministic, cross-language reproducible PRNG (xorshift32) and FNV-1a string hashing.
 * The GDScript port in apps/game/scripts/engine/rng.gd must produce identical streams.
 * Only integer operations are used so results are identical across platforms.
 */
export function fnv1a32(text: string): number {
  let h = 0x811c9dc5;
  const bytes = new TextEncoder().encode(text);
  for (const b of bytes) {
    h ^= b;
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

export class Rng {
  private state: number;

  constructor(seed: number) {
    // Mix the seed so that nearby seeds diverge quickly; never allow the zero state.
    let s = (seed >>> 0) ^ 0x9e3779b9;
    if (s === 0) s = 0x6d2b79f5;
    this.state = s >>> 0;
    for (let i = 0; i < 8; i++) this.nextU32();
  }

  nextU32(): number {
    let x = this.state;
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    this.state = x;
    return x;
  }

  /** Integer in [0, n). */
  int(n: number): number {
    if (n <= 0) throw new Error('Rng.int requires n > 0');
    return this.nextU32() % n;
  }

  /** Integer in [lo, hi] inclusive. */
  range(lo: number, hi: number): number {
    return lo + this.int(hi - lo + 1);
  }

  /** True with probability pct/100 (integer percent, no floating point). */
  chance(pct: number): boolean {
    return this.int(100) < pct;
  }

  /** In-place Fisher–Yates shuffle. */
  shuffle<T>(arr: T[]): T[] {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.int(i + 1);
      const tmp = arr[i] as T;
      arr[i] = arr[j] as T;
      arr[j] = tmp;
    }
    return arr;
  }

  pick<T>(arr: readonly T[]): T {
    return arr[this.int(arr.length)] as T;
  }
}
