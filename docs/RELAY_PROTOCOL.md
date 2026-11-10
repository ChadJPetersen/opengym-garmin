# Direct openGym watch-relay protocol

No demo server or new HTTP endpoint is needed. This watch uses upstream openGym **v1.4.4+**.

**Pair:** `POST /api/watch/redeem` with `{"code":"XXXX-XXXX-XXXX","name":"Garmin fenix 5S"}`, receiving `{"token":"ogw_..."}`. The code comes from signed-in openGym **Settings → Zepp OS watch → Pair a watch**. Watch stores the scoped token in Garmin `Application.Storage`.

**Read:** `GET /api/watch/box` with `Authorization: Bearer ogw_...` returns `{"json":"{...snapshot...}","at":epochMs}`. The `json` value contains the same upstream `watch-sync.js` snapshot that the Apple/Wear/Zepp watch implementations consume. It includes `active.id`, `active.cur`, `active.entries[].id`, `sets[].r/w/done`, `active.rest.endsAt` and `restSec`.

**Complete Set:** persist an event before sending; `POST /api/watch/box` with `{"events":[{"id":"unique","type":"setDone","wid":"workout-id","exId":"exercise-id","entryIdx":0,"setIdx":1,"w":60,"r":12,"at":1800000000000,"hr":{"avg":110,"max":130}}]}`. The response `accepted` array means **server queued** (not Android applied). Keep an awaiting list; a later snapshot with the matching set's `done:true` confirms application. Retry unsent events with the *same* id. The watch only displays the accelerometer estimate; it does not send that estimate as a fabricated actual rep count.

**Android app:** OpenGym's existing `startWatchRelay` and `watch-sync.js applyEvents` consume these events and invoke the real set-completion handler. When the phone is backgrounded, the mailbox retains the events until the app can process them. This is not an always-running background Android service.

**Deployment:** Home Assistant wrapper 1.4.3 lacks the upstream watch relay. Upgrade the wrapper's OpenGym API and web images to 1.4.4+. The existing HTTPS `/opengym/api/*` proxy suffices; do not publish an unencrypted new port.

**Acceptance tests still required:** actual Garmin SDK compilation; pairing through Garmin Connect on Android; HTTP responses and snapshot memory consumption on the original fēnix 5S; accurate set identity, offline queuing, deduplication and FIT heart-rate recording.
