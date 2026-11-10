# openGym Remote — Garmin fēnix 5S proof of concept

**Status: prototype.** A Connect IQ 3.1 watch app and dependency-free Node.js demo bridge. **This does not control your real openGym workouts or Android app yet.** The demo bridge simulates a workout in memory.

## Current features

- Shows exercise, current set, target reps/weight and a rest-time snapshot.
- UP/DOWN selects an action, START/ENTER sends it, MENU refreshes (physical button mappings need device testing).
- Available actions: `log_set`, `rest_plus_15`, `rest_minus_15`, `skip_rest`, `next_exercise`.
- HTTPS communications through the paired phone's Garmin Connect service.
- Dedicated bearer token rather than your openGym/Home Assistant credentials.
- Six automated bridge tests (Node 20+).

**Limitations:** No ticking timer, real workout synchronization, workout activity recording, or compiled/tested device build yet. The demo resets on restart, and command deduplication persists only until the bridge restarts.

## Get started

Install the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/overview/) and its VS Code Monkey C extension. The target device is the **original fēnix 5S** (`fenix5s`, Connect IQ 3.1).

You also need Node.js 20+ for the demo bridge.

```bash
npm test
export WATCH_TOKEN="$(node -e 'console.log(require("crypto").randomBytes(24).toString("hex"))')"
npm run dev
```

The bridge binds to `127.0.0.1:8787` by default. To inspect it locally:

```bash
curl -H "Authorization: Bearer $WATCH_TOKEN" http://127.0.0.1:8787/v1/state

curl -H "Authorization: Bearer $WATCH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"log_set","commandId":"manual-1"}' \
  http://127.0.0.1:8787/v1/commands
```

For a real watch, put the bridge behind an HTTPS reverse proxy with a publicly trusted certificate. Leave the bridge bound to loopback if the proxy is on the same machine; otherwise restrict the listener to an internal interface and firewall it. **Do not expose the demo HTTP service, or an unencrypted bearer token, directly to the Internet.** If serving it under a path such as `/gym-watch`, configure your proxy to strip that prefix before forwarding requests to the bridge.

## Build and configure the watch app

1. Open this repository in VS Code with the Monkey C extension and Connect IQ SDK configured.
2. Use `manifest.xml` and `monkey.jungle` to build the `fenix5s` target in the Garmin simulator.
3. In the Garmin Connect / Connect IQ app settings for **openGym Remote**, configure:
   - **Bridge base URL:** `https://your-domain.example/gym-watch` (no trailing slash)
   - **Dedicated watch token:** the value you generated as `WATCH_TOKEN`
4. Sync settings to the watch and launch the app. Refresh and try the demo actions.

The watch rejects non-HTTPS URLs. A production credential should be limited, revocable, and never be an openGym password, pairing code, or Home Assistant token. The SDK is not included here, and the Monkey C source **has not yet been compiled** in the packaging environment: compiler errors and key mappings may require fixes.

## Watch bridge HTTP contract

`GET /v1/state`, with header `Authorization: Bearer <watch-only-token>`, returns:

```json
{
  "exercise": "Hip Thrust",
  "setNumber": 2,
  "setCount": 4,
  "reps": 12,
  "weight": "135 lb",
  "restSeconds": 90,
  "version": 2,
  "completedSets": 1
}
```

`POST /v1/commands`, with the same authorization and `Content-Type: application/json`:

```json
{ "action": "log_set", "commandId": "1770000000-3" }
```

The response is the updated state object. A repeated command ID returns the cached first result instead of applying twice (in memory only). The watch does not automatically retry commands yet.

## Real OpenGym integration (next phase)

The bridge deliberately does not mutate upstream openGym's saved JSON or pretend that a simulated set is real. For full Android control:

1. Implement a scoped authenticated watch API and pair a watch to a specific user/device.
2. Have the Android app publish a compact snapshot of its actual workout state, including a session ID and monotonic revision.
3. Deliver watch commands to a phone-side adapter that invokes openGym's existing state-management actions (including its native rest-timer service).
4. ACK commands **only after** the phone processes them; reject stale workout sessions and deduplicate across restarts.
5. Show offline/queued/failed status clearly on the watch. Never falsely mark a set as logged.

Related upstream references:
- [openGym](https://github.com/DuarteSantos8/openGym)
- [React timer state](https://github.com/DuarteSantos8/openGym/blob/main/frontend/src/store/useUI.js)
- [Android rest timer](https://github.com/DuarteSantos8/openGym/blob/main/frontend/android/app/src/main/java/ch/duartesantos/opengym/RestTimerService.java)
- [Apple Watch session model](https://github.com/DuarteSantos8/openGym/blob/main/frontend/ios/App/Watch/SessionStore.swift)
- [Home Assistant openGym wrapper](https://github.com/ChadJPetersen/home-assistant-opengym)

## License

MIT for the code in this repository. Upstream openGym is separately AGPL-licensed; any copied or adapted upstream implementation must comply with its license.


## Heart-rate recording (prototype)

**Supported on the original fēnix 5S:** uses Toybox.Sensor (API 1.0+) for live BPM and Toybox.ActivityRecording (API 1.0+) for native Garmin FIT recording. The manifest requests Sensor and Fit permissions. Watch code still requires SDK compilation and testing on the real watch.

1. Open **openGym Remote**. Live HR appears as `HR xxx bpm`, or `HR -- bpm` if no reliable sensor reading is available.
2. UP/DOWN to **Start HR activity**, then START. This begins a Garmin FIT training activity with sensor heart rate; no server is necessary for FIT recording.
3. While recording, the app displays the current HR, average, and maximum. It samples at most once every five seconds for the demo bridge and sends batches of up to six readings, typically every 30 seconds, through HTTPS with the dedicated watch token.
4. Select **Save HR activity** to finish. If you exit while recording, the app attempts to save automatically. Garmin can sync the saved FIT activity to Garmin Connect through normal activity sync.

**Bridge HR endpoint:** Following a successful GET /v1/state, the watch uses the returned demo `sessionId` when POSTing `/v1/heart-rate` with JSON `{"sessionId":"...","samples":[{"t":1800000000,"bpm":120}]}`. Timestamps are Unix seconds. The authenticated GET `/v1/heart-rate` returns count, min, max, average, and latest BPM for the current demo session.

Each accepted sample is journaled to `data/heart-rate.jsonl` (override with `HR_DATA_FILE`), excluded from git. Secure and back up this private file. Samples are bounded, validated, and deduplicated by session/timestamp across bridge restarts.

**Important limits:** The FIT activity is separate from upstream openGym workout history. This bridge records only a demo workout, **not a real OpenGym workout**. The watch app must remain running to send bridge samples. Pending samples are buffered for up to 48 readings (about four minutes), but are **not persisted across watch app exits or crashes**. Garmin FIT is the more durable HR record. Network failures are retried at most about every 30 seconds; longer outages may lose bridge samples. Garmin Connect sync is handled by Garmin, not this demo bridge. Wrist heart rate is not intended for medical monitoring.

Next step: integrate the stream with real OpenGym workout IDs in the Android app/backend and avoid duplicate Health Connect workout sessions.


## Experimental automatic rep counting + Complete Set

The **original fēnix 5S** supports high-frequency accelerometer sensor data through Connect IQ 2.3+, so our Connect IQ 3.1 watch app can attempt wrist-based counting while the watch app is open.

The main screen shows:

```text
    Hip Thrust
      Set 2/4

 ESTIMATED / REQUIRED
       8 / 12

      HR 118 bpm
 Rest 0s | 135 lb

   > Complete Set <
```

**No rep/weight editing controls are needed on the watch.** The required count and weight come from the current workout snapshot. While not resting, the watch detects a cycle of motion away from its baseline wrist posture and back. It counts only plausible complete motions and deliberately ignores brief movement; it never automatically marks a set as complete. When the set is finished, **START / ENTER on "Complete Set"** checks off the current set through the authenticated `POST /v1/commands` bridge. UP/DOWN can reach the existing secondary rest, navigation and HR actions.

A completion request looks like this:

```json
{
  "action": "log_set",
  "commandId": "unique-request-id",
  "sessionId": "demo-workout-session-id",
  "setNumber": 2,
  "expectedVersion": 5,
  "estimatedReps": 8
}
```

The demo server validates the active session, set number and revision before marking the set complete, then advances the set/rest state and acknowledges the write. Duplicate request IDs don't complete the set twice. **Estimated reps are saved separately from required/target reps; even a zero estimate or missing sensor can still complete the set.** The planned target and weight are not modified.

### Current limitations and safety

- **This currently checks off sets in the demo bridge, not the actual Android openGym application.** The standalone OpenGym Android app needs an adapter to receive these commands and invoke its own existing `setDone` action before acknowledgments truly mean the phone updated. See [Android integration contract](docs/ANDROID_INTEGRATION.md).
- The motion detector is **experimental, not Garmin's proprietary Strength algorithm**. It is not exercise-aware, and needs real-device compilation and testing. Some leg exercises (leg press, hip thrust, leg curl) may produce nearly no wrist movement; the estimate may remain at zero.
- Sensors must be available, the watch app must be open, and the watch must be worn consistently. The counter recalibrates at the beginning of each set and pauses during the rest interval. False positives are still possible from motion unrelated to a rep.
- No automatic completion based on rep count. Pressing Complete Set is the only set-completion trigger.
- The estimated counter is currently held in watch RAM only. It does not survive closing/restarting the app.
- Do not treat the estimate as a verified exercise performance measurement. Make the eventual Android sync preserve target reps separately unless the user explicitly chooses to promote estimates to logged actual reps.
