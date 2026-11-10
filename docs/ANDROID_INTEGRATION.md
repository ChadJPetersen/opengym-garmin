# Android integration contract (not implemented yet)

The watch currently talks to an **authenticated demo bridge**. The real openGym Android application is the source of truth for workout state and must be the component that marks a set complete. Making a command return HTTP 200 without that phone-side acknowledgment would be misleading.

Upstream openGym already provides a watch event adapter in `frontend/src/lib/watch-sync.js`. Its `applyEvents` consumes events such as:

```json
{
  "id": "unique-watch-command-id",
  "type": "setDone",
  "wid": "real-openGym-workout-id",
  "exId": "exercise-id",
  "entryIdx": 0,
  "setIdx": 1,
  "at": 1800000000000
}
```

A Garmin controller command would need:

1. **Phone-side snapshot:** OpenGym publishes the actual workout ID, exercise ID, entry index, set index, target reps, target weight, set-done state, and version. Never use the demo's synthetic session ID as a real workout ID.
2. **Watch command:** The watch sends `complete_set`/our bridge's `log_set` with a durable unique command ID and the exact workout and set identity. Its `estimatedReps` is optional diagnostic metadata, **not an instruction to overwrite planned reps**.
3. **Phone-side apply:** Validate the session and state. Build a `setDone` event for the intended set. Pass it through the existing OpenGym workout handler (`bindWatchActions`), preserving existing rest timers, superset progression, high-water marks and history sync.
4. **Acknowledgment:** Do not ACK merely for accepting or queuing a command. ACK only after the phone applies (or explicitly confirms prior application of) the command. Do not send stale commands to a different workout.
5. **Recovery:** Keep a durable queue and command IDs through disconnections and app restarts. A duplicated command must not check off a second set. The watch should show `pending`/failure if it cannot confirm success.

**Important:** Upstream openGym v1.4.4 has Garmin watch UI/source and a compact Garmin snapshot, but its Garmin-specific Android Connect IQ Mobile SDK bridge is noted as not wired up in `docs/GARMIN.md`. That code targets Connect IQ 3.2+, which excludes the original fēnix 5S. This project retains a Connect IQ 3.1 target while following the existing OpenGym event model.

Relevant upstream sources:
- https://github.com/DuarteSantos8/openGym/blob/main/frontend/src/lib/watch-sync.js
- https://github.com/DuarteSantos8/openGym/blob/main/docs/GARMIN.md

This contract is design documentation; **no real Android OpenGym set-completion implementation has been merged here**.
