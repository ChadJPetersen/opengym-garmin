# Install on an original Garmin fēnix 5S (Windows)

**Current status:** prototype source only. No downloadable PRG release has been published and the Monkey C project has not yet passed a Garmin SDK/device build. You must compile it first and may encounter compile/device errors. GitHub Actions currently runs Node-based contract tests and manifest checks, not the Garmin SDK.

## Compile and sideload

1. From https://github.com/ChadJPetersen/opengym-garmin choose **Code → Download ZIP**, extract it and open the extracted project folder in **Visual Studio Code** (or use `git clone`).
2. Install the official **Garmin Connect IQ SDK Manager** from https://developer.garmin.com/connect-iq/sdk/ and choose the current SDK plus **fēnix 5S (original)** device files. Do not select fēnix 5S Plus.
3. Install the VS Code extension **Monkey C** (Garmin), and a supported Java runtime. Press `Ctrl+Shift+P` → **Monkey C: Verify Installation**.
4. Press `Ctrl+Shift+P` → **Monkey C: Generate a Developer Key**. Save the signing key **outside your repository**, and retain it for later updates.
5. First run **Monkey C: Build Current Project** or run in the `fenix5s` simulator to catch compile errors. Resolve build errors before continuing.
6. Run **Monkey C: Build for Device** → `fenix5s` → choose a destination folder. The result is a sideloadable `.PRG`.
7. Connect the fēnix 5S to Windows by USB. In File Explorer open the watch → `GARMIN\APPS`. Copy the `.PRG` there. Eject safely, unplug, and find **openGym Remote** under the watch's apps/activities.

Official instructions: https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/

## Important: configuration for sideloaded apps

**Garmin Connect / Connect IQ mobile generally cannot edit the settings of a sideloaded app.** The normal Connect IQ Store settings editor depends on the app being distributed through the store. This affects this project's two required settings: the OpenGym HTTPS server URL and one-time watch pairing code.

### Option A — for a sideloaded development build: copy simulator settings

1. Build and launch the same app in the Garmin **Connect IQ simulator** on Windows.
2. In the simulator, open **File → Edit Persistent Storage → Edit Application.Properties data** (wording may vary by SDK version).
3. Enter the OpenGym HTTPS base URL in **serverUrl**, such as `https://YOUR_HA_DOMAIN/opengym`, with no trailing slash.
4. In OpenGym 1.4.4+ on your phone or in a browser, open **Settings → Zepp OS watch → Pair a watch** to create a one-time code valid for **10 minutes**. Put that code into **pairingCode** in the simulator settings editor, then save.
5. With the simulator still running, find its generated settings file on your PC at approximately `%TEMP%\Garmin\Apps\Settings\<YOUR_APP_NAME>.SET`. Use File Explorer and sort by modified time if the exact filename is unclear.
6. Copy the `.SET` file to the watch's `GARMIN\APPS\SETTINGS` directory. The filename stem must **exactly match** the sideloaded `.PRG` filename (e.g. `OpenGym.PRG` and `OpenGym.SET`). If a default `.SET` exists there for that app, back it up before replacing it.
7. Safely eject the watch and launch **openGym Remote** while the pairing code is still valid. The app should redeem the code against `/api/watch/redeem`, store its dedicated watch token, and use `/api/watch/box` thereafter.

The `.SET` method has been documented by Garmin developers for sideloaded apps:
- https://forums.garmin.com/developer/connect-iq/f/discussion/253496/is-there-any-way-to-change-settings-in-sideloaded-app
- https://forums.garmin.com/developer/connect-iq/f/discussion/2121/modifying-settings-on-side-loaded-app/14323
- https://forums.garmin.com/developer/connect-iq/f/discussion/429848/solved-settings-connect-iq-app-for-sideloaded-app---is-this-possible

**Do not commit `.SET` files, pairing codes or any OpenGym credentials to GitHub.** The pairing code expires quickly, so prepare the simulator and USB transfer before generating it.

### Option B — for convenient phone settings: Connect IQ Store beta

You can package the project using **Monkey C: Export Project** and submit it as a **beta** through Garmin's Connect IQ developer dashboard. If Garmin accepts the beta submission and the original fēnix 5S remains an eligible target, installing the app through the store allows editing application settings in Garmin Connect / Connect IQ on the phone. It is a more convenient workflow after the initial build and review, but is not necessary for USB sideload testing.

## Before attempting a real workout

- Update the **Home Assistant openGym wrapper to 1.4.4-0+** (back up first), or use another OpenGym 1.4.4+ self-hosted server. Version 1.4.3 does not have the watch-relay API.
- Pair the official Android OpenGym app with **the same server and account**. Enable OpenGym's **Watch** module.
- Verify the OpenGym server's HTTPS certificate is trusted and that your proxy forwards `/opengym/api/watch/*` to the existing API.
- Test with a disposable workout first. The wrist-motion estimate is unvalidated; **Complete Set** sends actual set completion but the phone may not apply queued events until it is foregrounded.
- If Garmin's build produces compiler diagnostics, inspect/fix those before you copy the `.PRG`; a green Node-based CI run is not a successful Connect IQ device build.
