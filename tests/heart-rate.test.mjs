import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, test } from 'node:test';
import { DemoWorkout, makeServer } from '../bridge/server.mjs';
import { HeartRateStore } from '../bridge/hr-store.mjs';

const token = 'test-dedicated-watch-token-123456';
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'opengym-heart-rate-'));
const filePath = path.join(dir, 'heart-rate.jsonl');
const now = 1_800_000_000_000;
const workout = new DemoWorkout({ now: () => now });
const hrStore = new HeartRateStore({ filePath, now: () => now });
let server, base;

before(async () => {
  server = makeServer({ token, workout, hrStore });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = 'http://127.0.0.1:' + server.address().port;
});
after(async () => {
  await new Promise(resolve => server.close(resolve));
  fs.rmSync(dir, { recursive: true, force: true });
});

async function call(route, method = 'GET', body, secret = token) {
  const response = await fetch(base + route, {
    method,
    headers: { Authorization: 'Bearer ' + secret, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  return { status: response.status, data: await response.json() };
}
const t = Math.floor(now / 1000);

test('heart rate requires authorization', async () => {
  assert.equal((await call('/v1/heart-rate', 'GET', undefined, 'invalid')).status, 401);
  assert.equal((await call('/v1/heart-rate', 'POST', { sessionId: workout.sessionId, samples: [{ t, bpm: 120 }] }, 'invalid')).status, 401);
});

test('session in state identifies heart-rate stream', async () => {
  const r = await call('/v1/state');
  assert.equal(r.data.sessionId, workout.sessionId);
  assert.equal((await call('/v1/heart-rate')).data.count, 0);
});

test('timestamped readings persist and summaries are calculated', async () => {
  const r = await call('/v1/heart-rate', 'POST', {
    sessionId: workout.sessionId, samples: [{ t: t - 10, bpm: 100 }, { t: t - 5, bpm: 140 }, { t, bpm: 120 }]
  });
  assert.equal(r.status, 200);
  assert.equal(r.data.accepted, 3);
  assert.deepEqual({ count: r.data.summary.count, average: r.data.summary.averageBpm, peak: r.data.summary.maxBpm }, { count: 3, average: 120, peak: 140 });
  assert.equal(fs.readFileSync(filePath, 'utf8').trim().split('\n').length, 3);
});

test('retries are idempotent and do not duplicate journal entries', async () => {
  const r = await call('/v1/heart-rate', 'POST', { sessionId: workout.sessionId, samples: [{ t, bpm: 120 }] });
  assert.equal(r.data.accepted, 0);
  assert.equal(r.data.duplicates, 1);
  assert.equal((await call('/v1/heart-rate')).data.count, 3);
});

test('stale session, invalid BPM, invalid time and oversized batches are rejected', async () => {
  assert.equal((await call('/v1/heart-rate', 'POST', { sessionId: 'stale-session', samples: [{ t, bpm: 99 }] })).status, 409);
  for (const samples of [[{ t, bpm: 999 }], [{ t: t + 301, bpm: 120 }], Array.from({ length: 13 }, (_, i) => ({ t: t - i, bpm: 120 }))]) {
    assert.equal((await call('/v1/heart-rate', 'POST', { sessionId: workout.sessionId, samples })).status, 400);
  }
  assert.equal((await call('/v1/heart-rate')).data.count, 3);
});

test('recorded readings reload from the journal after restart', () => {
  const loaded = new HeartRateStore({ filePath, now: () => now });
  assert.equal(loaded.summary(workout.sessionId).count, 3);
  assert.equal(loaded.summary(workout.sessionId).maxBpm, 140);
});
