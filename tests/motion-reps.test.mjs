import assert from 'node:assert/strict';
import { test } from 'node:test';
import { MotionRepCounter } from './support/motion-reps.mjs';

const sample = (c, x, z, t) => c.feed(x, 0, z, t);

// 25 Hz, starting at a stationary resting posture; one roughly 1-second
// wrist rotation from the resting position and back.
function baseline(c, t = 0) {
  for (let i = 0; i < 20; i++) sample(c, 0, 1000, t + i * 40);
  return t + 800;
}
function rep(c, t, amplitude = 700, steps = 35) {
  for (let i = 0; i < steps; i++) {
    const a = Math.sin(Math.PI * i / (steps - 1));
    sample(c, Math.round(amplitude * a), Math.round(1000 - amplitude * 0.45 * a), t + i * 40);
  }
  for (let i = 0; i < 5; i++) sample(c, 0, 1000, t + (steps + i) * 40);
  return t + (steps + 5) * 40;
}

test('consistent wrist movements count one per full return to rest', () => {
  const c = new MotionRepCounter();
  let t = baseline(c);
  for (let i = 0; i < 6; i++) t = rep(c, t);
  assert.equal(c.reps, 6);
});

test('stationary leg work cannot be inferred from a motionless wrist', () => {
  const c = new MotionRepCounter();
  for (let i = 0; i < 500; i++) sample(c, 0, 1000, i * 40);
  assert.equal(c.reps, 0);
});

test('small motion, fidget and partial movement do not count', () => {
  const c = new MotionRepCounter();
  let t = baseline(c);
  t = rep(c, t, 100);
  // One very short motion (0.16 s), with return to rest.
  for (let i = 0; i < 4; i++) sample(c, 700, 700, t + i * 40);
  for (let i = 0; i < 12; i++) sample(c, 0, 1000, t + 160 + i * 40);
  assert.equal(c.reps, 0);
});

test('a static shifted wrist position eventually recalibrates rather than counting', () => {
  const c = new MotionRepCounter();
  let t = baseline(c);
  for (let i = 0; i < 190; i++) sample(c, 650, 760, t + i * 40);
  assert.equal(c.reps, 0);
});

test('starting a new set resets calibration and reps', () => {
  const c = new MotionRepCounter();
  const t = baseline(c);
  rep(c, t);
  assert.equal(c.reps, 1);
  c.reset();
  assert.equal(c.reps, 0);
  baseline(c);
  assert.equal(c.reps, 0);
});

test('invalid accelerometer samples are ignored', () => {
  const c = new MotionRepCounter();
  baseline(c);
  c.feed(null, 10, 10, 1000);
  c.feed(Number.NaN, 10, 10, 1040);
  assert.equal(c.reps, 0);
});
