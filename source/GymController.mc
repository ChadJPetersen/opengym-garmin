import Toybox.ActivityRecording;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// Directly uses upstream openGym's authenticated watch-relay endpoints.
// NO DEMO SERVER: /api/watch/redeem and /api/watch/box on your own openGym server.
// SetDone enters the upstream mailbox and is applied by openGym's existing
// watch-sync.js when the Android app or web client processes it.
class GymController {
    var exercise = "Open OpenGym";
    var setNumber = 0;
    var setCount = 0;
    var reps = 0;
    var weight = "";
    var restSeconds = 0;
    var status = "Configure OpenGym";
    var selected = 0;
    var busy = false;
    var mode = "";
    var lastRequestAt = 0;
    var timer = null;
    var serverUrl = null;
    var token = null;

    var workoutId = "";
    var exerciseId = "";
    var entryIdx = 0;
    var setIdx = 0;
    var weightValue = 0.0;
    var currentSetKey = "";
    var cachedJson = null;
    var outbox = [];
    var awaiting = [];
    var activeSnapshot = null;
    var localRestEndsAt = 0.toLong();

    var motionCounter = new MotionReps();
    var motionAvailable = false;
    var motionRate = 25;
    var heartRate = 0;
    var heartRateAt = 0;
    var setHeartTotal = 0;
    var setHeartCount = 0;
    var setHeartMax = 0;

    var recording = false;
    var fitSession = null;
    var recordedHeartTotal = 0;
    var recordedHeartCount = 0;
    var recordedHeartMax = 0;

    var names = [ "Complete Set", "Refresh", "Record HR" ];

    function initialize() {
        outbox = Storage.getValue("outbox");
        if (!(outbox instanceof Array)) { outbox = []; }
        awaiting = Storage.getValue("awaiting");
        if (!(awaiting instanceof Array)) { awaiting = []; }
        token = Storage.getValue("watchToken");
        if (!(token instanceof String) || token.length() < 8) { token = null; }
        serverUrl = Application.getApp().getProperty("serverUrl");
        if (!(serverUrl instanceof String) || serverUrl.substring(0, 8) != "https://") {
            serverUrl = null;
        } else {
            while (serverUrl.length() > 0 && serverUrl.substring(serverUrl.length() - 1, serverUrl.length()) == "/") {
                serverUrl = serverUrl.substring(0, serverUrl.length() - 1);
            }
        }
    }

    function startSensors() {
        try {
            Sensor.setEnabledSensors([ Sensor.SENSOR_HEARTRATE ]);
            Sensor.enableSensorEvents(method(:onSensor));
        } catch (ex) { status = "HR sensor unavailable"; }
        try {
            var rate = Sensor.getMaxSampleRate();
            if (rate != null && rate >= 10) {
                if (rate > 25) { rate = 25; }
                motionRate = rate;
                Sensor.registerSensorDataListener(method(:onMotion), {
                    :period => 1,
                    :accelerometer => { :enabled => true, :sampleRate => rate }
                });
                motionAvailable = true;
            }
        } catch (ex) { motionAvailable = false; }
        timer = new Timer.Timer();
        timer.start(method(:tick), 1000, true);
        refresh();
    }

    function shutDown() {
        if (timer != null) { timer.stop(); timer = null; }
        try { Sensor.unregisterSensorDataListener(); } catch (ex) { }
        try { Sensor.enableSensorEvents(null); Sensor.setEnabledSensors([]); } catch (ex) { }
        if (recording) { finishRecording(); }
        saveQueue();
    }

    function saveQueue() {
        try {
            Storage.setValue("outbox", outbox);
            Storage.setValue("awaiting", awaiting);
        } catch (ex) { status = "Cannot save watch queue"; }
    }

    function nowMillis() {
        return Time.now().value().toLong() * 1000;
    }

    function currentRest() {
        var until = localRestEndsAt;
        if (activeSnapshot != null && activeSnapshot["restEndsAt"] > until) {
            until = activeSnapshot["restEndsAt"];
        }
        var seconds = (until - nowMillis()) / 1000;
        return seconds > 0 ? seconds.toNumber() : 0;
    }

    function tick() {
        restSeconds = currentRest();
        if (!busy && System.getTimer() - lastRequestAt >= 15000) {
            refresh();
        }
        WatchUi.requestUpdate();
    }

    function moveSelection(delta) {
        selected = (selected + delta + names.size()) % names.size();
        WatchUi.requestUpdate();
    }

    function selectedName() {
        if (selected == 2) { return recording ? "Save HR activity" : "Start HR activity"; }
        return names[selected];
    }

    function estimatedReps() {
        return motionAvailable ? motionCounter.count.toString() : "--";
    }

    function heartText() {
        if (heartRate == 0 || Time.now().value() - heartRateAt > 15) {
            return recording ? "HR -- REC" : "HR -- bpm";
        }
        return "HR " + heartRate.toString() + (recording ? " REC" : " bpm");
    }

    function heartStats() {
        if (recordedHeartCount == 0) { return "AVG -- / MAX --"; }
        return "AVG " + (recordedHeartTotal / recordedHeartCount).toString()
            + " / MAX " + recordedHeartMax.toString();
    }

    function onSensor(info) {
        var bpm = info.heartRate;
        if (bpm == null || bpm < 30 || bpm > 240) {
            heartRate = 0;
            return;
        }
        heartRate = bpm;
        heartRateAt = Time.now().value();
        if (recording) {
            recordedHeartTotal += bpm;
            recordedHeartCount += 1;
            if (bpm > recordedHeartMax) { recordedHeartMax = bpm; }
        }
        if (currentSetKey != "" && currentRest() == 0) {
            setHeartTotal += bpm;
            setHeartCount += 1;
            if (bpm > setHeartMax) { setHeartMax = bpm; }
        }
        WatchUi.requestUpdate();
    }

    function onMotion(data) {
        if (!motionAvailable || currentSetKey == "" || currentRest() > 0) { return; }
        if (data == null || data.accelerometerData == null) { return; }
        var a = data.accelerometerData;
        if (a.x == null || a.y == null || a.z == null) { return; }
        var n = a.x.size();
        if (a.y.size() < n) { n = a.y.size(); }
        if (a.z.size() < n) { n = a.z.size(); }
        var step = 1000.0 / motionRate;
        var now = System.getTimer();
        var before = motionCounter.count;
        for (var i = 0; i < n; i += 1) {
            motionCounter.feed(a.x[i], a.y[i], a.z[i], now - (n - 1 - i) * step);
        }
        if (motionCounter.count != before) { WatchUi.requestUpdate(); }
    }

    function startRecording() {
        if (recording) { return; }
        try {
            fitSession = ActivityRecording.createSession({
                :name => "openGym", :sport => ActivityRecording.SPORT_TRAINING
            });
            if (fitSession == null) { status = "FIT unavailable"; return; }
            fitSession.start();
            recording = true;
            recordedHeartCount = 0;
            recordedHeartTotal = 0;
            recordedHeartMax = 0;
            status = "Garmin HR recording";
        } catch (ex) {
            recording = false;
            fitSession = null;
            status = "FIT start failed";
        }
        WatchUi.requestUpdate();
    }

    function finishRecording() {
        if (!recording) { return; }
        recording = false;
        try {
            fitSession.stop();
            fitSession.save();
            status = "FIT activity saved";
        } catch (ex) { status = "FIT save failed"; }
        fitSession = null;
        WatchUi.requestUpdate();
    }

    function selectAction() {
        if (selected == 2) {
            if (recording) { finishRecording(); }
            else { startRecording(); }
        } else if (selected == 1) { refresh(); }
        else { completeSet(); }
    }

    function setKey(wid, idx, si) {
        return wid + ":" + idx.toString() + ":" + si.toString();
    }

    function keyIn(collection, key) {
        for (var i = 0; i < collection.size(); i += 1) {
            if (collection[i] == key) { return true; }
        }
        return false;
    }

    function allLocalKeys() {
        var keys = awaiting.slice(0, null);
        for (var i = 0; i < outbox.size(); i += 1) {
            var ev = outbox[i];
            keys.add(setKey(ev["wid"], ev["entryIdx"], ev["setIdx"]));
        }
        return keys;
    }

    function refreshDisplay() {
        if (!(cachedJson instanceof String)) { return; }
        var parser = new WatchSnapshot(cachedJson);
        var snap = parser.read(allLocalKeys());
        var confirmed = snap["confirmed"];
        var remaining = [];
        var changed = false;
        for (var i = 0; i < awaiting.size(); i += 1) {
            if (!keyIn(confirmed, awaiting[i])) { remaining.add(awaiting[i]); }
            else { changed = true; }
        }
        if (changed) {
            awaiting = remaining;
            saveQueue();
            snap = parser.read(allLocalKeys());
        }
        activeSnapshot = snap;
        var key = "";
        if (snap["found"]) {
            key = setKey(snap["workoutId"], snap["entryIdx"], snap["setIdx"]);
            workoutId = snap["workoutId"];
            exerciseId = snap["exerciseId"];
            entryIdx = snap["entryIdx"];
            setIdx = snap["setIdx"];
            exercise = snap["exercise"];
            setNumber = snap["setNumber"];
            setCount = snap["setCount"];
            reps = snap["reps"];
            weightValue = snap["weight"];
            weight = snap["weightText"] + " " + snap["unit"];
        } else {
            exercise = snap["workoutId"] == "" ? "OpenGym: no workout" : "All sets queued/done";
            workoutId = snap["workoutId"];
            exerciseId = "";
            setNumber = 0;
            setCount = 0;
            reps = 0;
            weight = "";
        }
        if (key != currentSetKey) {
            currentSetKey = key;
            motionCounter.reset();
            setHeartTotal = 0;
            setHeartCount = 0;
            setHeartMax = 0;
        }
        restSeconds = currentRest();
        if (changed) { status = "Set checked in app"; }
        else if (outbox.size() > 0 || awaiting.size() > 0) { status = "Queued for OpenGym"; }
        else { status = "OpenGym connected"; }
        WatchUi.requestUpdate();
    }

    function completeSet() {
        if (currentSetKey == "" || workoutId == "") {
            status = "No open set"; WatchUi.requestUpdate(); return;
        }
        if (outbox.size() >= 24) {
            status = "Queue full - open app"; WatchUi.requestUpdate(); return;
        }
        // OpenGym's setDone uses the existing planned 'r' and 'w'. The motion
        // estimate is informational and NEVER overwrites the required reps.
        var id = "f5s-" + Time.now().value().toString() + "-" + System.getTimer().toString();
        var ev = {
            "id" => id, "type" => "setDone", "wid" => workoutId,
            "exId" => exerciseId, "entryIdx" => entryIdx, "setIdx" => setIdx,
            "w" => weightValue, "r" => reps, "at" => nowMillis()
        };
        if (setHeartCount > 0) {
            ev["hr"] = { "avg" => setHeartTotal / setHeartCount, "max" => setHeartMax };
        }
        outbox.add(ev);
        saveQueue(); // Persist before network: a crash cannot silently lose a set.
        var rest = activeSnapshot != null ? activeSnapshot["defaultRest"] : 90;
        if (rest == null || rest < 0 || rest > 3600) { rest = 90; }
        // The phone's own rest timer starts when it applies the event. Until
        // then use a watch-local countdown; don't claim it changed the app.
        localRestEndsAt = nowMillis() + rest * 1000;
        refreshDisplay(); // Advance locally, including other queued sets.
        status = "Queued - not yet applied";
        if (!busy) { sendNext(); }
        WatchUi.requestUpdate();
    }

    function requestHeaders(includeToken) {
        var h = { "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON };
        if (includeToken) { h["Authorization"] = "Bearer " + token; }
        return h;
    }

    function makeRequest(path, payload, kind) {
        if (busy || serverUrl == null) { return; }
        busy = true;
        mode = kind;
        lastRequestAt = System.getTimer();
        var post = payload != null;
        try {
            Communications.makeWebRequest(serverUrl + path, payload,
                { :method => post ? Communications.HTTP_REQUEST_METHOD_POST : Communications.HTTP_REQUEST_METHOD_GET,
                  :headers => requestHeaders(kind != "redeem"),
                  :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON },
                method(:onResponse));
        } catch (ex) {
            busy = false;
            mode = "";
            status = "Garmin connection failed";
            WatchUi.requestUpdate();
        }
    }

    function refresh() {
        if (busy) { return; }
        if (serverUrl == null) {
            status = "Set HTTPS OpenGym URL"; WatchUi.requestUpdate(); return;
        }
        if (token == null) {
            var pairing = Application.getApp().getProperty("pairingCode");
            if (!(pairing instanceof String) || pairing.length() < 12) {
                status = "Pair in OpenGym settings"; WatchUi.requestUpdate(); return;
            }
            status = "Pairing watch...";
            makeRequest("/api/watch/redeem",
                { "code" => pairing, "name" => "Garmin fenix 5S" }, "redeem");
            return;
        }
        if (outbox.size() > 0) { sendNext(); return; }
        makeRequest("/api/watch/box", null, "snapshot");
    }

    function sendNext() {
        if (busy || token == null || outbox.size() == 0) { return; }
        status = "Sending set to OpenGym";
        makeRequest("/api/watch/box", { "events" => [ outbox[0] ] }, "events");
    }

    function onResponse(code, body) {
        var kind = mode;
        busy = false;
        mode = "";
        if (code == 401 && kind != "redeem") {
            token = null;
            Storage.deleteValue("watchToken");
            status = "Pairing expired - pair again";
            WatchUi.requestUpdate();
            return;
        }
        if (code != 200 || !(body instanceof Dictionary)) {
            status = "OpenGym HTTP " + code.toString();
            WatchUi.requestUpdate();
            return;
        }
        if (kind == "redeem") {
            var received = body["token"];
            if (!(received instanceof String) || received.substring(0, 4) != "ogw_") {
                status = "Invalid pairing response"; return;
            }
            token = received;
            Storage.setValue("watchToken", token);
            status = "Watch paired";
            WatchUi.requestUpdate();
            return;
        }

        if (kind == "events" && outbox.size() > 0) {
            var accepted = body["accepted"];
            var id = outbox[0]["id"];
            var confirmed = false;
            if (accepted instanceof Array) {
                for (var i = 0; i < accepted.size(); i += 1) {
                    if (accepted[i] == id) { confirmed = true; break; }
                }
            }
            if (!confirmed) {
                status = "Server did not queue set";
                WatchUi.requestUpdate();
                return;
            }
            var ev = outbox[0];
            outbox = outbox.slice(1, null);
            var key = setKey(ev["wid"], ev["entryIdx"], ev["setIdx"]);
            if (!keyIn(awaiting, key)) { awaiting.add(key); }
            saveQueue();
        }
        if (body["json"] instanceof String) {
            cachedJson = body["json"];
            refreshDisplay();
        } else if (kind == "snapshot") {
            status = "Open OpenGym on phone";
        }
        if (kind == "events") {
            status = "Queued for OpenGym";
        }
        WatchUi.requestUpdate();
        if (kind == "events" && outbox.size() > 0) { sendNext(); }
    }
}
