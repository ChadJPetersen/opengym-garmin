import Toybox.Application;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
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

    var actionNames = [ "Log set", "Rest +15", "Rest -15", "Skip rest", "Next exercise", "Refresh" ];
    var actionIds = [ "log_set", "rest_plus_15", "rest_minus_15", "skip_rest", "next_exercise", "refresh" ];

    function initialize() { }

    function moveSelection(delta) {
        selected = (selected + delta + actionNames.size()) % actionNames.size();
        WatchUi.requestUpdate();
    }

    function selectedName() {
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
        if (busy) { return; }
        if (actionIds[selected] == "refresh") { refresh(); return; }
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
            var payload = { "action" => actionIds[selected], "commandId" => id };
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
            status = "HTTP/network: " + code.toString();
            WatchUi.requestUpdate();
            return;
        }
        if (!(body instanceof Dictionary)) {
            status = "Bad server response";
            WatchUi.requestUpdate();
            return;
        }
        // Clamp/validate every field because response data is untrusted.
        if (body["exercise"] instanceof String) { exercise = body["exercise"]; }
        if (body["setNumber"] instanceof Number) { setNumber = body["setNumber"]; }
        if (body["setCount"] instanceof Number) { setCount = body["setCount"]; }
        if (body["reps"] instanceof Number) { reps = body["reps"]; }
        if (body["weight"] instanceof String) { weight = body["weight"]; }
        if (body["restSeconds"] instanceof Number) { restSeconds = body["restSeconds"]; }
        if (body["version"] instanceof Number) { version = body["version"]; }
        status = "Synced v" + version.toString();
        WatchUi.requestUpdate();
    }
}
