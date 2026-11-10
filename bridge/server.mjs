import http from 'node:http';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// DEMO ONLY. No OpenGym APIs are called and no real workout is modified.
// Production: replace DemoWorkout with an authenticated live-workout adapter.
export class DemoWorkout {
  constructor({ now = () => Date.now() } = {}) {
    this.now = now;
    this.exercises = [
      { name: 'Hip Thrust', reps: 12, weight: '135 lb', sets: 4 },
      { name: 'RDL', reps: 10, weight: '95 lb', sets: 3 },
      { name: 'Abduction', reps: 15, weight: '80 lb', sets: 3 }
    ];
    this.exerciseIndex = 0;
    this.completedSets = 0;
    this.restEndsAt = 0;
    this.version = 1;
    this.seenCommands = new Map();
  }
  state() {
    const e = this.exercises[this.exerciseIndex];
    return {
      exercise: e.name,
      setNumber: Math.min(this.completedSets + 1, e.sets),
      setCount: e.sets,
      reps: e.reps,
      weight: e.weight,
      restSeconds: Math.max(0, Math.ceil((this.restEndsAt - this.now()) / 1000)),
      version: this.version,
      completedSets: this.completedSets
    };
  }
  command(id, action) {
    if (this.seenCommands.has(id)) return this.seenCommands.get(id);
    const e = this.exercises[this.exerciseIndex];
    switch (action) {
      case 'log_set':
        if (this.completedSets >= e.sets) throw new CommandError(409, 'All sets logged; select next exercise');
        this.completedSets += 1;
        this.restEndsAt = this.now() + 90_000;
        break;
      case 'rest_plus_15':
        this.restEndsAt = Math.max(this.now(), this.restEndsAt) + 15_000;
        break;
      case 'rest_minus_15':
        this.restEndsAt = Math.max(this.now(), this.restEndsAt - 15_000);
        break;
      case 'skip_rest':
        this.restEndsAt = 0;
        break;
      case 'next_exercise':
        this.exerciseIndex = (this.exerciseIndex + 1) % this.exercises.length;
        this.completedSets = 0;
        this.restEndsAt = 0;
        break;
      default: throw new CommandError(400, 'Unknown action');
    }
    this.version += 1;
    const result = this.state();
    this.seenCommands.set(id, result);
    if (this.seenCommands.size > 256) {
      this.seenCommands.delete(this.seenCommands.keys().next().value);
    }
    return result;
  }
}

class CommandError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function tokenMatches(provided, expected) {
  if (!provided || !expected) return false;
  const left = Buffer.from(provided, 'utf8');
  const right = Buffer.from(expected, 'utf8');
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function reply(res, status, payload) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'"
  });
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  let text = '';
  for await (const chunk of req) {
    text += chunk;
    if (text.length > 4096) throw new CommandError(413, 'Body too large');
  }
  try { return JSON.parse(text); }
  catch { throw new CommandError(400, 'Invalid JSON'); }
}

export function makeServer({ token, workout = new DemoWorkout() }) {
  if (!token || token.length < 16) throw new Error('WATCH_TOKEN must have at least 16 characters');
  return http.createServer(async (req, res) => {
    const path = new URL(req.url, 'http://localhost').pathname;
    const bearer = req.headers.authorization?.startsWith('Bearer ')
      ? req.headers.authorization.slice(7) : null;
    if (!tokenMatches(bearer, token)) return reply(res, 401, { error: 'Unauthorized' });
    try {
      if (req.method === 'GET' && path === '/v1/state') return reply(res, 200, workout.state());
      if (req.method === 'POST' && path === '/v1/commands') {
        if (!req.headers['content-type']?.startsWith('application/json')) {
          return reply(res, 415, { error: 'Expected application/json' });
        }
        const body = await readJson(req);
        if (!body || typeof body.action !== 'string' || typeof body.commandId !== 'string'
            || !/^[a-z0-9_]{2,24}$/.test(body.action)
            || !/^[a-zA-Z0-9_-]{1,90}$/.test(body.commandId)) {
          return reply(res, 400, { error: 'Invalid command' });
        }
        return reply(res, 200, workout.command(body.commandId, body.action));
      }
      return reply(res, 404, { error: 'Not found' });
    } catch (err) {
      return reply(res, err.status || 500, { error: err.status ? err.message : 'Internal error' });
    }
  });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === fileURLToPath(new URL(`file://${process.argv[1]}`))) {
  const token = process.env.WATCH_TOKEN;
  const port = Number(process.env.PORT || 8787);
  const host = process.env.HOST || '127.0.0.1';
  const server = makeServer({ token });
  server.listen(port, host, () => {
    console.log(`DEMO bridge on http://${host}:${port} (HTTPS reverse proxy required for watch)`);
  });
}
