# openGym Remote — Garmin fēnix 5S

**Experimental direct integration with self-hosted openGym 1.4.4+.** A Connect IQ 3.1 watch application for the original fēnix 5S that reads real workout sets, displays **estimated reps / required reps**, and sends **Complete Set** to the existing openGym watch relay. **No demo server or extra Home Assistant port.**

## Features

- Real exercise, target reps, weight and set progress from openGym's `watch-sync.js` snapshot.
- Wrist-motion estimate (experimental; the required reps are never edited).
- START/ENTER with **Complete Set** selected submits an upstream `setDone` event with the real workout/set identifiers.
- Resilient event outbox on the watch: locally queued sets advance immediately; the server queues the events for openGym to process.
- **Queued** means the server received the event, not that the Android app applied it. **Set checked in app** is shown only when a later real workout snapshot marks the set done.
- Live heart rate, per-set avg/max HR included in the set event, optional native Garmin FIT activity recording.
- No OpenGym password, Home Assistant token, or full account session stored on the watch; uses a revocable dedicated watch token.

## Install on an original fēnix 5S

This is a **source-only prototype**; no prebuilt Garmin `.PRG` is available yet. Use the [Windows sideload installation guide](docs/SIDELOAD.md) to compile the `fenix5s` target and copy it over USB.

**Critical:** Apps installed by copying a `.PRG` generally **cannot have their settings edited in Garmin Connect**. For sideload testing, use the Garmin simulator to generate and copy a matching `.SET` settings file (explained in that guide), or use a Garmin Connect IQ Store beta distribution after compilation.

## Pairing


1. **Required:** update your self-hosted OpenGym to **1.4.4 or newer**. The Home Assistant wrapper previously pinned 1.4.3, which lacks these relay endpoints. Back up the app before upgrading.
2. Connect the official Android openGym app to that self-hosted server, not local-only mode. Ensure the **Watch** module is enabled.
3. In the signed-in OpenGym app or web UI, open **Settings → Zepp OS watch → Pair a watch**. This creates a watch-relay code valid for **10 minutes**. We reuse the same generic server mailbox, not a Zepp device.
4. In Garmin Connect / Connect IQ settings for **openGym Remote**, configure:
   - **OpenGym HTTPS URL:** `https://YOUR_HA_DOMAIN/opengym` for your existing Home Assistant HTTPS mobile API path (or the root URL of your independent server). No `/api/watch` suffix.
   - **One-time pairing code:** the `XXXX-XXXX-XXXX` value from step 3.
5. Open the watch app. It redeems the code at `/api/watch/redeem` and stores the watch-only `ogw_...` token privately in Garmin Application.Storage. You can clear the code field after pairing.
6. Start an actual workout on Android, leaving the app open briefly to publish the snapshot. The watch will show the current exercise and `estimated / required` reps.
7. Press **Complete Set**. Its native `setDone` event is sent to `/api/watch/box`. The server queues it until the OpenGym mobile/web frontend processes it, at which point the set is really checked off.

The phone can be locked during lifting; **its WebView may be suspended**, so queued set completions are not guaranteed to appear in Android until the app is opened again. The watch can queue multiple sets independently. There is no claim of immediate phone-side application while suspended.

## Buttons

| Button | Action |
|---|---|
| START / ENTER | Complete Set (default selected action) |
| UP / DOWN | Change selected action (Complete Set, Refresh, Start/Save HR activity) |
| MENU | Refresh current openGym snapshot |
| BACK | Exit watch app |

The watch displays the motion **estimate** but sends the **required target** as `r` in OpenGym's upstream `setDone` event. This avoids falsely converting wrist movement into verified reps.

## Limitations and verification

- The Garmin Monkey C source **has not yet been compiled against the actual fēnix 5S device files or tested on that watch**. Network behavior, memory constraints and motion detection need device verification.
- The 5S has limited Connect IQ memory. The watch reads the built-in OpenGym relay's `json` snapshot string with a selective parser rather than creating a complete second JSON tree, but very large workouts may exceed memory.
- Accelerometer counting is heuristic: hip thrusts, leg presses and other leg exercises may have little wrist movement. A zero estimate does **not** prevent Complete Set.
- The upstream watch relay supports `setDone` events but not native watch commands to change Android's active rest timer or exercise selection. A watch-local rest countdown is informational until the app applies the set.
- Full heart-rate samples belong to the optional Garmin FIT recording; the `setDone` event includes set avg/max HR.
- Android must be signed in to this same server for the relay to work; local-only phone mode cannot use it.

## Development

`npm test` runs the reference motion-detector tests and static wire-contract checks (Node 20+). It **does not compile Monkey C** or exercise Garmin's Bluetooth/HTTP stack.

Use the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) and install the **fenix5s** device files. Build `monkey.jungle` for that target, then test both foreground and locked-phone behavior.

See [real relay protocol](docs/RELAY_PROTOCOL.md) for API details. Relevant upstream code: [watch relay](https://github.com/DuarteSantos8/openGym/blob/v1.4.4/api/watch-relay.js), [watch event consumer](https://github.com/DuarteSantos8/openGym/blob/v1.4.4/frontend/src/lib/watch-sync.js), and [Zepp relay documentation](https://github.com/DuarteSantos8/openGym/blob/v1.4.4/docs/ZEPP_OS.md).

## Automated maintenance

The repository has a [daily upstream release watcher](.github/workflows/check-upstream.yml) that opens compatibility issues and a [monthly Codex agent](.github/workflows/monthly-garmin-agent.yml) that proposes tested fixes, improvements and new features as reviewable pull requests. **Nothing is auto-merged.** The monthly agent requires an `OPENAI_API_KEY` GitHub Actions secret in this repository and permission for Actions to create pull requests. See [automation setup and safeguards](docs/AUTOMATION.md).

## License

MIT for this repository's original code. Upstream OpenGym is separately AGPL-licensed.
