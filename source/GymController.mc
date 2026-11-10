import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The bridge contract is intentionally small. It is NOT the upstream openGym API.
// All writes require a separately issued, revocable WATCH token. Never use a
// personal OpenGym password, pairing code, Home Assistant token, or session key.
class GymController {
    var exercise = "No workout loaded";
    var setNumber = 0;
    var setCount = 0;
    var reps = 0;
    var weight = "";
    var restSeconds = 0;
    var status = "Open app settings";
    var busy = false;
    var selected = 0;
    var version = 0;
    var sequence = 0;
    var sessionId = null;

    var heartRate = 0;
    var heartRateAt = 0;
    var heartSamples = 0;
    var heartTotal = 0;
    var heartMax = 0;
    var lastSampleAt = 0;
    var recording = false;
    var fitSession = null;
    var heartPending = [];
    var heartSending = false;
    var heartSendingCount = 0;
    var heartNextRetryAt = 0;
    var heartDropped = 0;
    var motionCounter = new MotionReps();
    var motionAvailable = false;
    var motionRate = 25;
    var selectedSetKey = "";
    var setFinished = false;
    var restDeadline = 0;
    var ticker = null;
    var pendingAction = null;

    var actionNames = [ "Complete Set", "Rest +15", "Rest -15", "Skip rest", "Next exercise", "Refresh", "Record HR" ];
    var actionIds = [ "log_set", "rest_plus_15", "rest_minus_15", "skip_rest", "next_exercise", "refresh", "toggle_hr" ];

    function initialize() { }

    function startSensors() {
        try {
            Sensor.setEnabledSensors([ Sensor.SENSOR_HEARTRATE ]);
            Sensor.enableSensorEvents(method(:onSensor));
            startMotion();
            ticker = new Timer.Timer();
            ticker.start(method(:tick), 1000, true);
        } catch (ex) {
            status = "HR sensor unavailable";
        }
    }

    function startMotion() {
        try {
            var rate = Sensor.getMaxSampleRate();
            if (rate == null || rate < 10) { return; }
            if (rate > 25) { rate = 25; }
            motionRate = rate;
            Sensor.registerSensorDataListener(method(:onMotion), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => rate }
            });
            motionAvailable = true;
        } catch (ex) {
            motionAvailable = false;
        }
    }

    function onMotion(packet) {
        if (!countingEnabled()) { return; }
        if (packet == null || packet.accelerometerData == null) { return; }
        var a = packet.accelerometerData;
        if (a.x == null || a.y == null || a.z == null) { return; }
        var n = a.x.size();
        if (a.y.size() < n) { n = a.y.size(); }
        if (a.z.size() < n) { n = a.z.size(); }
        var now = System.getTimer();
        var step = 1000.0 / motionRate;
        var before = motionCounter.count;
        for (var i = 0; i < n; i += 1) {
            // Older Connect IQ versions provide batches without per-sample timestamps.
            motionCounter.feed(a.x[i], a.y[i], a.z[i], now - (n - 1 - i) * step);
        }
        if (motionCounter.count != before) { WatchUi.requestUpdate(); }
    }

    function countingEnabled() {
        return motionAvailable && sessionId != null && setNumber > 0 && !setFinished
               && restSeconds <= 0 && !busy;
    }

    function estimatedReps() {
        return motionAvailable ? motionCounter.count.toString() : "--";
    }

    function tick() {
        if (restDeadline > 0 && restSeconds > 0) {
            var left = Math.ceil((restDeadline - System.getTimer()) / 1000.0);
            if (left <= 0) {
                restDeadline = 0;
                restSeconds = 0;
                motionCounter.reset();
                status = "Rest over";
            } else {
                restSeconds = left;
            }
            WatchUi.requestUpdate();
        }
        if (!recording && heartPending.size() > 0) { maybeSendHeartRate(true); }
    }

    function stopSensors() {
        if (ticker != null) { ticker.stop(); ticker = null; }
        try { Sensor.unregisterSensorDataListener(); } catch (ex) { }
        try {
            Sensor.enableSensorEvents(null);
            Sensor.setEnabledSensors([]);
        } catch (ex) { }
    }

    function shutDown() {
        if (recording) { finishRecording(); }
        stopSensors();
        // A pending request is not guaranteed to complete as the app closes.
        // Garmin's saved FIT activity is the durable recording in this case.
    }

    function startRecording() {
        if (recording) { return; }
        try {
            fitSession = ActivityRecording.createSession({
                :name => "openGym",
                :sport => ActivityRecording.SPORT_TRAINING
            });
            if (fitSession == null || !fitSession.start()) {
                fitSession = null;
                status = "Cannot start FIT";
                WatchUi.requestUpdate();
                return;
            }
            recording = true;
            heartSamples = 0;
            heartTotal = 0;
            heartMax = 0;
            heartDropped = 0;
            lastSampleAt = 0;
            status = "Recording Garmin FIT";
        } catch (ex) {
            fitSession = null;
            recording = false;
            status = "FIT recording failed";
        }
        WatchUi.requestUpdate();
    }

    function finishRecording() {
        if (!recording) { return; }
        recording = false;
        var ok = false;
        try {
            if (fitSession != null) {
                fitSession.stop();
                ok = fitSession.save();
            }
        } catch (ex) { }
        fitSession = null;
        // An incomplete final batch is also sent when possible.
        maybeSendHeartRate(true);
        status = ok ? "HR activity saved" : "FIT save failed";
        WatchUi.requestUpdate();
    }

    function heartText() {
        if (heartRate == 0 || Time.now().value() - heartRateAt > 15) {
            return recording ? "HR -- bpm REC" : "HR -- bpm";
        }
        return "HR " + heartRate.toString() + " bpm" + (recording ? " REC" : "");
    }

    function heartStats() {
        if (heartSamples == 0) { return "AVG -- / MAX --"; }
        return "AVG " + (heartTotal / heartSamples).toString() + " / MAX " + heartMax.toString();
    }

    function onSensor(info) {
        var bpm = info.heartRate;
        if (bpm == null || bpm < 30 || bpm > 240) {
            heartRate = 0;
            WatchUi.requestUpdate();
            return;
        }
        heartRate = bpm;
        var now = Time.now().value();
        heartRateAt = now;
        if (recording && now - lastSampleAt >= 5) {
            lastSampleAt = now;
            heartSamples += 1;
            heartTotal += bpm;
            if (bpm > heartMax) { heartMax = bpm; }
            if (heartPending.size() < 48) {
                heartPending.add({ "t" => now, "bpm" => bpm });
            } else {
                heartDropped += 1;
            }
            maybeSendHeartRate(false);
        } else if (!recording && heartPending.size() > 0) {
            // Retry a short final batch after recording ends while the app is open.
            maybeSendHeartRate(true);
        }
        WatchUi.requestUpdate();
    }

    function maybeSendHeartRate(force) {
        if (heartSending || busy || sessionId == null || heartPending.size() == 0) { return; }
        if (!force && heartPending.size() < 6) { return; }
        if (Time.now().value() < heartNextRetryAt) { return; }
        var base = apiBase();
        var headers = authHeaders();
        if (base == null || headers == null) { return; }
        heartSendingCount = heartPending.size();
        if (heartSendingCount > 6) { heartSendingCount = 6; }
        var batch = heartPending.slice(0, heartSendingCount);
        heartSending = true;
        try {
            Communications.makeWebRequest(base + "/v1/heart-rate",
                { "sessionId" => sessionId, "samples" => batch },
                { :method => Communications.HTTP_REQUEST_METHOD_POST,
                  :headers => headers,
                  :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onHeartResponse));
        } catch (ex) {
            heartSending = false;
            heartNextRetryAt = Time.now().value() + 30;
        }
    }

    function onHeartResponse(code, body) {
        heartSending = false;
        if (code == 200 && body instanceof Dictionary) {
            heartPending = heartPending.slice(heartSendingCount, null);
            heartNextRetryAt = 0;
            if (heartPending.size() > 0) { maybeSendHeartRate(!recording); }
        } else {
            heartNextRetryAt = Time.now().value() + 30;
            // A 409 means the bridge restarted or switched demo sessions.
            // Discard unmatched bridge samples (Garmin FIT still keeps HR).
            if (code == 409) {
                sessionId = null;
                heartPending = [];
            }
        }
        WatchUi.requestUpdate();
    }


    function moveSelection(delta) {
        selected = (selected + delta + actionNames.size()) % actionNames.size();
        WatchUi.requestUpdate();
    }

    function selectedName() {
        if (actionIds[selected] == "toggle_hr") {
            return recording ? "Save HR activity" : "Start HR activity";
        }
        return actionNames[selected];
    }

    function apiBase() {
        var url = Application.getApp().getProperty("serverUrl");
        if (url == null || !(url instanceof String) || url.length() < 9) {
            return null;
        }
        // Avoid accepting an HTTP endpoint that could expose a watch credential.
        if (url.substring(0, 8) != "https://") {
            return null;
        }
        while (url.length() > 0 && url.substring(url.length() - 1, url.length()) == "/") {
            url = url.substring(0, url.length() - 1);
        }
        return url;
    }

    function authHeaders() {
        var token = Application.getApp().getProperty("watchToken");
        if (token == null || !(token instanceof String) || token.length() == 0) {
            return null;
        }
        return { "Authorization" => "Bearer " + token,
                 "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };
    }

    function refresh() {
        if (busy) { return; }
        var base = apiBase();
        var headers = authHeaders();
        if (base == null || headers == null) {
            status = "Set HTTPS URL + token";
            WatchUi.requestUpdate();
            return;
        }
        busy = true;
        status = "Refreshing...";
        WatchUi.requestUpdate();
        try {
            Communications.makeWebRequest(base + "/v1/state", null,
                { :method => Communications.HTTP_REQUEST_METHOD_GET,
                  :headers => headers,
                  :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onResponse));
        } catch (ex) {
            busy = false;
            status = "Connection unavailable";
            WatchUi.requestUpdate();
        }
    }

    function selectAction() {
        if (actionIds[selected] == "toggle_hr") {
            if (recording) { finishRecording(); } else { startRecording(); }
            return;
        }
        if (busy) { return; }
        if (actionIds[selected] == "refresh") { refresh(); return; }
        if (actionIds[selected] == "log_set" && (sessionId == null || setFinished || setNumber == 0)) {
            status = "No open set";
            WatchUi.requestUpdate();
            return;
        }
        var base = apiBase();
        var headers = authHeaders();
        if (base == null || headers == null) {
            status = "Set HTTPS URL + token";
            WatchUi.requestUpdate();
            return;
        }
        sequence += 1;
        var id = Time.now().value().toString() + "-" + System.getTimer().toString() + "-" + sequence.toString();
        busy = true;
        status = "Sending...";
        WatchUi.requestUpdate();
        try {
            var action = actionIds[selected];
            var payload = { "action" => action, "commandId" => id };
            if (action == "log_set") {
                payload["sessionId"] = sessionId;
                payload["setNumber"] = setNumber;
                payload["expectedVersion"] = version;
                // Estimated count is metadata, not the workout's required reps.
                payload["estimatedReps"] = motionAvailable ? motionCounter.count : null;
            }
            pendingAction = action;
            Communications.makeWebRequest(base + "/v1/commands", payload,
                { :method => Communications.HTTP_REQUEST_METHOD_POST,
                  :headers => headers,
                  :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onResponse));
        } catch (ex) {
            busy = false;
            status = "Unable to send";
            WatchUi.requestUpdate();
        }
    }

    function onResponse(code, body) {
        busy = false;
        if (code != 200) {
            pendingAction = null;
            status = code == 409 ? "Workout changed: refresh" : "HTTP/network: " + code.toString();
            WatchUi.requestUpdate();
            return;
        }
        if (!(body instanceof Dictionary)) {
            pendingAction = null;
            status = "Bad server response";
            WatchUi.requestUpdate();
            return;
        }
        // Clamp/validate every field because response data is untrusted.
        var actionDone = pendingAction;
        pendingAction = null;
        var oldKey = selectedSetKey;
        if (body["exercise"] instanceof String) { exercise = body["exercise"]; }
        if (body["setNumber"] instanceof Number) { setNumber = body["setNumber"]; }
        if (body["setCount"] instanceof Number) { setCount = body["setCount"]; }
        if (body["reps"] instanceof Number) { reps = body["reps"]; }
        if (body["weight"] instanceof String) { weight = body["weight"]; }
        if (body["restSeconds"] instanceof Number) { restSeconds = body["restSeconds"]; }
        if (body["version"] instanceof Number) { version = body["version"]; }
        if (body["sessionId"] instanceof String) { sessionId = body["sessionId"]; }
        if (body["currentSetDone"] instanceof Boolean) { setFinished = body["currentSetDone"]; }
        selectedSetKey = sessionId + ":" + exercise + ":" + setNumber.toString();
        if (oldKey != selectedSetKey || actionDone == "log_set") { motionCounter.reset(); }
        restDeadline = restSeconds > 0 ? System.getTimer() + restSeconds * 1000 : 0;
        status = actionDone == "log_set" ? "Set checked off" : "Synced v" + version.toString();
        maybeSendHeartRate(!recording);
        WatchUi.requestUpdate();
    }
}
