import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { DemoWorkout, makeServer } from '../bridge/server.mjs';

const TOKEN = 'test-dedicated-watch-token-123456';
let server, base;
const now = () => 100000;

before(async () => {
  server = makeServer({ token: TOKEN, workout: new DemoWorkout({ now }) });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await new Promise(resolve => server.close(resolve)); });

async function request(path, { token = TOKEN, method = 'GET', body, contentType = 'application/json' } = {}) {
  const response = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': contentType } : {})
    },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  return { code: response.status, json: await response.json() };
}

test('unauthorized requests are rejected', async () => {
  assert.equal((await request('/v1/state', { token: '' })).code, 401);
  assert.equal((await request('/v1/state', { token: 'wrong' })).code, 401);
});

test('state is a compact JSON workout snapshot', async () => {
  const { code, json } = await request('/v1/state');
  assert.equal(code, 200);
  assert.equal(json.exercise, 'Hip Thrust');
  assert.equal(json.setNumber, 1);
  assert.equal(json.restSeconds, 0);
});

test('commands mutate demo state and duplicate ids are idempotent', async () => {
  const current = (await request('/v1/state')).json;
  const command = { action: 'log_set', commandId: 'command-100',
    sessionId: current.sessionId, setNumber: current.setNumber,
    expectedVersion: current.version, estimatedReps: 8 };
  const first = await request('/v1/commands', { method: 'POST', body: command });
  assert.equal(first.code, 200);
  assert.equal(first.json.setNumber, 2);
  assert.equal(first.json.lastLoggedEstimate, 8);
  assert.equal(first.json.reps, 12);
  assert.equal(first.json.restSeconds, 90);
  const duplicate = await request('/v1/commands', { method: 'POST', body: command });
  assert.deepEqual(duplicate.json, first.json);
  assert.equal((await request('/v1/state')).json.completedSets, 1);
});

test('rest adjustments and skip work', async () => {
  const plus = await request('/v1/commands', { method: 'POST', body: { action: 'rest_plus_15', commandId: 'command-101' } });
  assert.equal(plus.json.restSeconds, 105);
  const minus = await request('/v1/commands', { method: 'POST', body: { action: 'rest_minus_15', commandId: 'command-102' } });
  assert.equal(minus.json.restSeconds, 90);
  const skip = await request('/v1/commands', { method: 'POST', body: { action: 'skip_rest', commandId: 'command-103' } });
  assert.equal(skip.json.restSeconds, 0);
});

test('next exercise changes active exercise', async () => {
  const next = await request('/v1/commands', { method: 'POST', body: { action: 'next_exercise', commandId: 'command-104' } });
  assert.equal(next.json.exercise, 'RDL');
  assert.equal(next.json.setNumber, 1);
});

test('invalid command and content-type are rejected', async () => {
  assert.equal((await request('/v1/commands', { method: 'POST', body: { action: 'hack', commandId: 'command-105' } })).code, 400);
  assert.equal((await request('/v1/commands', { method: 'POST', body: { action: 'log_set', commandId: 'command-106' }, contentType: 'text/plain' })).code, 415);
});
