// Reference implementation for testing the lightweight Monkey C rep detector.
// Units: accelerometer millig (mg), timestamps milliseconds.
// This does NOT have access to Garmin's proprietary built-in Strength rep counter.
export class MotionRepCounter {
  constructor() { this.reset(); }
  reset() {
    this.reps = 0;
    this.samples = 0;
    this.bx = 0; this.by = 0; this.bz = 0;
    this.fx = 0; this.fy = 0; this.fz = 0;
    this.away = false;
    this.departedAt = 0;
    this.returnStartedAt = -1;
    this.lastRepAt = -10000;
  }
  feed(x, y, z, atMs) {
    if (![x, y, z, atMs].every(Number.isFinite)) return this.reps;
    if (this.samples < 12) {
      this.samples++;
      this.bx += (x - this.bx) / this.samples;
      this.by += (y - this.by) / this.samples;
      this.bz += (z - this.bz) / this.samples;
      this.fx = this.bx; this.fy = this.by; this.fz = this.bz;
      return this.reps;
    }
    this.fx += (x - this.fx) * 0.35;
    this.fy += (y - this.fy) * 0.35;
    this.fz += (z - this.fz) * 0.35;
    const dx = this.fx - this.bx;
    const dy = this.fy - this.by;
    const dz = this.fz - this.bz;
    const distanceSq = dx * dx + dy * dy + dz * dz;
    if (!this.away) {
      if (distanceSq > 260 * 260) {
        this.away = true;
        this.departedAt = atMs;
        this.returnStartedAt = -1;
      } else if (distanceSq < 150 * 150) {
        this.bx += (this.fx - this.bx) * 0.002;
        this.by += (this.fy - this.by) * 0.002;
        this.bz += (this.fz - this.bz) * 0.002;
      }
    } else {
      if (distanceSq < 150 * 150) {
        if (this.returnStartedAt < 0) this.returnStartedAt = atMs;
        if (atMs - this.returnStartedAt >= 120) {
          const duration = atMs - this.departedAt;
          if (duration >= 450 && duration <= 5500 && atMs - this.lastRepAt >= 500) {
            this.reps++;
            this.lastRepAt = atMs;
          }
          this.away = false;
          this.returnStartedAt = -1;
        }
      } else {
        this.returnStartedAt = -1;
      }
      if (atMs - this.departedAt > 5500) {
        // The wrist is in a new posture, not a finished rep; re-base without counting.
        this.away = false;
        this.returnStartedAt = -1;
        this.bx = this.fx; this.by = this.fy; this.bz = this.fz;
      }
    }
    return this.reps;
  }
}
