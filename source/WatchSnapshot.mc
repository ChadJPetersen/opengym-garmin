// Reads only the active workout fields from openGym's EXISTING watch-relay
// snapshot JSON string. Does not materialize the entire ~48 KB JSON tree.
// OpenGym's /api/watch/box responds {json: "...", at: epochMs}.
import Toybox.Lang;

class WatchSnapshot {
    var textValue;
    var lengthValue;

    function initialize(json) {
        textValue = json;
        lengthValue = json.length();
    }

    function ch(i) {
        return textValue.substring(i, i + 1);
    }

    function ws(i) {
        while (i < lengthValue) {
            var c = ch(i);
            if (c != " " && c != "\n" && c != "\r" && c != "\t") { break; }
            i += 1;
        }
        return i;
    }

    // Return the byte following the closing quote, skipping backslash escapes.
    function stringEnd(at) {
        if (at < 0 || at >= lengthValue || ch(at) != "\"") { return -1; }
        var i = at + 1;
        while (i < lengthValue) {
            var c = ch(i);
            if (c == "\\") { i += 2; continue; }
            if (c == "\"") { return i + 1; }
            i += 1;
        }
        return -1;
    }

    // Skip a JSON value (including all nested structures), without allocating.
    function skipValue(at) {
        var i = ws(at);
        if (i < 0 || i >= lengthValue) { return -1; }
        var first = ch(i);
        if (first == "\"") { return stringEnd(i); }
        if (first == "{" || first == "[") {
            var depth = 0;
            while (i < lengthValue) {
                var c = ch(i);
                if (c == "\"") {
                    i = stringEnd(i);
                    if (i < 0) { return -1; }
                    continue;
                }
                if (c == "{" || c == "[") { depth += 1; }
                if (c == "}" || c == "]") {
                    depth -= 1;
                    if (depth == 0) { return i + 1; }
                    if (depth < 0) { return -1; }
                }
                i += 1;
            }
            return -1;
        }
        while (i < lengthValue) {
            var c = ch(i);
            if (c == "," || c == "}" || c == "]" || c == " " || c == "\n") { return i; }
            i += 1;
        }
        return i;
    }

    function readString(at) {
        if (at < 0 || at >= lengthValue || ch(at) != "\"") { return ""; }
        var end = stringEnd(at);
        if (end < 0) { return ""; }
        var result = "";
        var i = at + 1;
        while (i < end - 1) {
            var c = ch(i);
            if (c == "\\" && i + 1 < end - 1) {
                i += 1;
                var next = ch(i);
                if (next == "n") { result += " "; }
                else if (next == "t") { result += " "; }
                else if (next == "r") { result += " "; }
                else if (next == "\"" || next == "\\" || next == "/") { result += next; }
                else if (next == "u" && i + 4 < end - 1) {
                    // Unicode escapes in names are rare; keep a readable placeholder.
                    result += "?";
                    i += 4;
                }
            } else { result += c; }
            i += 1;
        }
        return result;
    }

    function readScalar(at) {
        if (at < 0 || at >= lengthValue) { return ""; }
        var i = ws(at);
        var end = skipValue(i);
        if (end < i || ch(i) == "{" || ch(i) == "[" || ch(i) == "\"") { return ""; }
        return textValue.substring(i, end);
    }

    function readInt(at, fallback) {
        var scalar = readScalar(at);
        if (scalar.length() == 0) { return fallback; }
        try { return scalar.toNumber(); } catch (ex) { return fallback; }
    }

    function readFloat(at, fallback) {
        var scalar = readScalar(at);
        if (scalar.length() == 0) { return fallback; }
        try { return scalar.toFloat(); } catch (ex) { return fallback; }
    }

    function readLong(at, fallback) {
        var scalar = readScalar(at);
        if (scalar.length() == 0) { return fallback; }
        try { return scalar.toLong(); } catch (ex) { return fallback; }
    }

    function readBool(at) {
        return readScalar(at) == "true";
    }

    // Location of the named field's VALUE within an object, not a parsed copy.
    function field(objectAt, wanted) {
        if (objectAt < 0 || objectAt >= lengthValue) { return -1; }
        var i = ws(objectAt);
        if (ch(i) != "{") { return -1; }
        i = ws(i + 1);
        while (i >= 0 && i < lengthValue && ch(i) != "}") {
            if (ch(i) != "\"") { return -1; }
            var key = readString(i);
            i = stringEnd(i);
            if (i < 0) { return -1; }
            i = ws(i);
            if (ch(i) != ":") { return -1; }
            i = ws(i + 1);
            if (key == wanted) { return i; }
            i = skipValue(i);
            if (i < 0) { return -1; }
            i = ws(i);
            if (ch(i) == ",") { i = ws(i + 1); }
            else if (ch(i) != "}") { return -1; }
        }
        return -1;
    }

    function arrCount(at) {
        if (at < 0 || at >= lengthValue || ch(ws(at)) != "[") { return 0; }
        var i = ws(at + 1);
        var n = 0;
        while (i < lengthValue && ch(i) != "]" && n < 200) {
            i = skipValue(i);
            if (i < 0) { return 0; }
            n += 1;
            i = ws(i);
            if (ch(i) == ",") { i = ws(i + 1); }
            else if (ch(i) != "]") { return 0; }
        }
        return n;
    }

    function arrAt(at, index) {
        if (at < 0 || at >= lengthValue || ch(ws(at)) != "[") { return -1; }
        var i = ws(at + 1);
        for (var n = 0; n < index; n += 1) {
            if (ch(i) == "]") { return -1; }
            i = skipValue(i);
            if (i < 0) { return -1; }
            i = ws(i);
            if (ch(i) != ",") { return -1; }
            i = ws(i + 1);
        }
        if (ch(i) == "]") { return -1; }
        return i;
    }

    function keyFor(wid, idx, setIdx) {
        return wid + ":" + idx.toString() + ":" + setIdx.toString();
    }

    function contains(keys, key) {
        for (var i = 0; i < keys.size(); i += 1) {
            if (keys[i] == key) { return true; }
        }
        return false;
    }

    // Produces a compact view and confirmed IDs for queue-reconciliation.
    function read(keys) {
        var out = { "found" => false, "workoutId" => "", "exercise" => "",
            "exerciseId" => "", "entryIdx" => 0, "setIdx" => 0, "setNumber" => 0,
            "setCount" => 0, "reps" => 0, "weight" => 0.0, "weightText" => "",
            "unit" => "kg", "restEndsAt" => 0.toLong(), "confirmed" => [] };
        if (lengthValue > 49152 || lengthValue < 3) { return out; }
        var active = field(0, "active");
        if (active < 0 || ch(active) != "{") { return out; }
        var wid = readString(field(active, "id"));
        if (wid.length() == 0) { return out; }
        out["workoutId"] = wid;
        var entries = field(active, "entries");
        var n = arrCount(entries);
        if (n == 0) { return out; }
        var cur = readInt(field(active, "cur"), 0);
        if (cur < 0 || cur >= n) { cur = 0; }
        var unit = readString(field(active, "unit"));
        if (unit == "") { unit = readString(field(0, "unit")); }
        out["unit"] = unit == "lb" ? "lb" : "kg";
        var rest = field(active, "rest");
        if (rest >= 0 && ch(rest) == "{") {
            out["restEndsAt"] = readLong(field(rest, "endsAt"), 0.toLong());
        }

        var candidate = null;
        for (var i = 0; i < n; i += 1) {
            var idx = (cur + i) % n;
            var e = arrAt(entries, idx);
            var sets = field(e, "sets");
            var setCount = arrCount(sets);
            var mode = readString(field(e, "mode"));
            for (var si = 0; si < setCount; si += 1) {
                var st = arrAt(sets, si);
                var key = keyFor(wid, idx, si);
                if (readBool(field(st, "done"))) {
                    out["confirmed"].add(key);
                    continue;
                }
                if (candidate == null && !contains(keys, key) && mode != "cardio") {
                    candidate = { "found" => true, "workoutId" => wid,
                        "exercise" => readString(field(e, "name")),
                        "exerciseId" => readString(field(e, "id")),
                        "entryIdx" => idx, "setIdx" => si, "setNumber" => si + 1,
                        "setCount" => setCount,
                        "reps" => readInt(field(st, "r"), 0),
                        "weight" => readFloat(field(st, "w"), 0.0),
                        "weightText" => readScalar(field(st, "w")),
                        "unit" => out["unit"], "restEndsAt" => out["restEndsAt"] };
                }
            }
        }
        if (candidate == null) { return out; }
        candidate["confirmed"] = out["confirmed"];
        return candidate;
    }
}
