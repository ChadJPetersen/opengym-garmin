import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const file = name => fs.readFileSync(path.join(root, name), 'utf8');
const ctrl = file('source/GymController.mc');
const parser = file('source/WatchSnapshot.mc');

test('watch communicates with upstream openGym API, not an independent demo server', () => {
  assert.match(ctrl, /\/api\/watch\/redeem/);
  assert.match(ctrl, /\/api\/watch\/box/);
  assert.doesNotMatch(ctrl, /\/v1\/commands|\/v1\/state|\/v1\/heart-rate/);
  assert.equal(fs.existsSync(path.join(root, 'bridge/server.mjs')), false);
  assert.equal(fs.existsSync(path.join(root, 'bridge/hr-store.mjs')), false);
});

test('setDone payload identifies a real workout and set; it is persisted before transmission', () => {
  for (const field of ['"id"', '"type"', '"wid"', '"exId"', '"entryIdx"', '"setIdx"', '"w"', '"r"', '"at"']) {
    assert.ok(ctrl.includes(field + ' => '), field + ' missing');
  }
  assert.match(ctrl, /"type" => "setDone"/);
  assert.match(ctrl, /outbox\.add\(ev\);\s*saveQueue\(\)/);
  assert.match(ctrl, /"events" => \[ outbox\[0\] \]/);
  assert.match(ctrl, /body\["accepted"\]/);
  assert.match(parser, /"done"/);
});

test('paired watch only stores the scoped watch credential, not a login token', () => {
  assert.match(ctrl, /Storage\.setValue\("watchToken", token\)/);
  assert.match(ctrl, /"ogw_"/);
  assert.match(ctrl, /h\["Authorization"\] = "Bearer " \+ token/);
  assert.doesNotMatch(ctrl, /password|gymsid|homeassistant.*token/i);
});

test('set estimate does not overwrite required reps and parser identifies actual sets', () => {
  assert.match(ctrl, /"r" => reps/);
  assert.match(ctrl, /motionCounter\.count/);
  assert.match(parser, /field\(active, "entries"\)/);
  assert.match(parser, /field\(st, "done"\)/);
  assert.match(parser, /field\(st, "r"\)/);
  assert.match(parser, /field\(st, "w"\)/);
});

test('watch settings contain an HTTPS base address and one-time pairing code', () => {
  const xml = file('resources/settings.xml');
  assert.match(xml, /Properties\.serverUrl/);
  assert.match(xml, /Properties\.pairingCode/);
  assert.doesNotMatch(xml, /Properties\.watchToken/);
  const conf = file('resources/properties.xml');
  assert.match(conf, /pairingCode/);
});
