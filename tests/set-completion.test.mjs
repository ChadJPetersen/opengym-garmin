import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DemoWorkout } from '../bridge/server.mjs';

function complete(model, id, estimatedReps, overrides = {}) {
  return model.command(id, 'log_set', {
    sessionId: model.sessionId,
    setNumber: model.completedSets + 1,
    expectedVersion: model.version,
    estimatedReps,
    ...overrides
  });
}

test('Complete Set checks off the current set; target remains unchanged', () => {
  const model = new DemoWorkout({ now: () => 100000 });
  const result = complete(model, 'set-a', 8);
  assert.equal(result.completedSets, 1);
  assert.equal(result.setNumber, 2);
  assert.equal(result.reps, 12);
  assert.equal(result.lastLoggedEstimate, 8);
  assert.deepEqual(model.loggedSets[0], {
    exercise: 'Hip Thrust', setNumber: 1,
    targetReps: 12, estimatedReps: 8, weight: '135 lb', at: 100000
  });
});

test('zero and unavailable counts can still complete an exercise', () => {
  const model = new DemoWorkout();
  assert.equal(complete(model, 'no-movement', 0).completedSets, 1);
  assert.equal(complete(model, 'no-sensor', null).completedSets, 2);
  assert.equal(model.loggedSets[1].estimatedReps, null);
});

test('stale set or session cannot be checked off', () => {
  const model = new DemoWorkout();
  assert.throws(() => complete(model, 'stale', 9, { expectedVersion: 0 }), /changed/);
  assert.throws(() => complete(model, 'wrong', 9, { sessionId: 'another-session' }), /changed/);
  assert.throws(() => complete(model, 'skip', 9, { setNumber: 3 }), /changed/);
  assert.equal(model.loggedSets.length, 0);
});

test('same request ID only completes one set', () => {
  const model = new DemoWorkout();
  const request = {
    sessionId: model.sessionId, setNumber: 1, expectedVersion: 1, estimatedReps: 9
  };
  const result = model.command('one', 'log_set', request);
  assert.equal(model.command('one', 'log_set', request).version, result.version);
  assert.throws(() => model.command('one', 'log_set', { ...request, estimatedReps: 10 }), /different data/);
  assert.equal(model.loggedSets.length, 1);
});

test('invalid estimated reps are refused without completing a set', () => {
  const model = new DemoWorkout();
  for (const count of [-1, 101, '12', 1.7]) {
    assert.throws(() => complete(model, 'bad-' + String(count), count), /Invalid/);
  }
  assert.equal(model.state().completedSets, 0);
});
