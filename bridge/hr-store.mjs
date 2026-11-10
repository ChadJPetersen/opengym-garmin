import fs from 'node:fs';
import path from 'node:path';

// Demo heart-rate journal; this is NOT an upstream openGym data format.
// Keep this file in private storage, never inside git or a public web directory.
export class HeartRateStore {
  constructor({ filePath = process.env.HR_DATA_FILE || path.resolve('data/heart-rate.jsonl'), now = () => Date.now() } = {}) {
    this.filePath = filePath;
    this.now = now;
    this.seen = new Set();
    this.summaries = new Map();
    if (fs.existsSync(this.filePath)) {
      for (const line of fs.readFileSync(this.filePath, 'utf8').split('\n')) {
        if (!line.trim()) continue;
        try {
          const record = JSON.parse(line);
          if (this.validRecord(record)) this.accumulate(record);
        } catch { /* skip incomplete or corrupt journal lines */ }
      }
    }
  }

  validRecord(record) {
    return record && typeof record.sessionId === 'string' && record.sessionId.length < 128
      && Number.isSafeInteger(record.t) && Number.isInteger(record.bpm)
      && record.bpm >= 30 && record.bpm <= 240;
  }

  accumulate(record) {
    const key = record.sessionId + ':' + record.t;
    if (this.seen.has(key)) return false;
    this.seen.add(key);
    const old = this.summaries.get(record.sessionId) || {
      count: 0, totalBpm: 0, minBpm: 240, maxBpm: 0, latestAt: 0, latestBpm: null
    };
    old.count += 1;
    old.totalBpm += record.bpm;
    old.minBpm = Math.min(old.minBpm, record.bpm);
    old.maxBpm = Math.max(old.maxBpm, record.bpm);
    if (record.t >= old.latestAt) {
      old.latestAt = record.t;
      old.latestBpm = record.bpm;
    }
    this.summaries.set(record.sessionId, old);
    return true;
  }

  summary(sessionId) {
    const s = this.summaries.get(sessionId);
    if (!s) return { sessionId, count: 0, averageBpm: null, minBpm: null, maxBpm: null, latestAt: null, latestBpm: null };
    return {
      sessionId, count: s.count, averageBpm: Math.round(s.totalBpm / s.count),
      minBpm: s.minBpm, maxBpm: s.maxBpm, latestAt: s.latestAt, latestBpm: s.latestBpm
    };
  }

  append(sessionId, samples) {
    if (typeof sessionId !== 'string' || !/^[a-zA-Z0-9_-]{1,90}$/.test(sessionId)) {
      throw Object.assign(new Error('Invalid session ID'), { status: 400 });
    }
    if (!Array.isArray(samples) || samples.length < 1 || samples.length > 12) {
      throw Object.assign(new Error('Expected 1–12 heart-rate samples'), { status: 400 });
    }
    const nowSeconds = Math.floor(this.now() / 1000);
    for (const sample of samples) {
      if (!sample || !Number.isSafeInteger(sample.t) || sample.t < nowSeconds - 7 * 86400 || sample.t > nowSeconds + 300
        || !Number.isInteger(sample.bpm) || sample.bpm < 30 || sample.bpm > 240) {
        throw Object.assign(new Error('Invalid heart-rate sample'), { status: 400 });
      }
    }
    const fresh = [];
    const inBatch = new Set();
    for (const sample of samples) {
      const key = sessionId + ':' + sample.t;
      if (!this.seen.has(key) && !inBatch.has(key)) {
        fresh.push({ sessionId, t: sample.t, bpm: sample.bpm });
        inBatch.add(key);
      }
    }
    if (fresh.length) {
      fs.mkdirSync(path.dirname(this.filePath), { recursive: true, mode: 0o700 });
      fs.appendFileSync(this.filePath, fresh.map(value => JSON.stringify(value)).join('\n') + '\n', { mode: 0o600 });
      for (const record of fresh) this.accumulate(record);
    }
    return { accepted: fresh.length, duplicates: samples.length - fresh.length, summary: this.summary(sessionId) };
  }
}
