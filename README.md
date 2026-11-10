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
