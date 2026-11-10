// Experimental 3-axis wrist-cycle detector for original fēnix 5S.
// Accelerometer axes are reported in milli-g. Count only a motion that leaves
// a calibrated resting pose and returns; this does not identify the exercise.
// Intentionally conservative. Validate on real workouts before trusting it.
class MotionReps {
    var count = 0;
    var samples = 0;
    var bx = 0.0;
    var by = 0.0;
    var bz = 0.0;
    var fx = 0.0;
    var fy = 0.0;
    var fz = 0.0;
    var away = false;
    var departedAt = 0;
    var returnSince = -1;
    var lastRepAt = -10000;

    function initialize() {
        reset();
    }

    function reset() {
        count = 0;
        samples = 0;
        bx = 0.0; by = 0.0; bz = 0.0;
        fx = 0.0; fy = 0.0; fz = 0.0;
        away = false;
        departedAt = 0;
        returnSince = -1;
        lastRepAt = -10000;
    }

    function feed(x, y, z, atMs) {
        if (x == null || y == null || z == null) { return; }
        if (samples < 12) {
            samples += 1;
            bx += (x - bx) / samples;
            by += (y - by) / samples;
            bz += (z - bz) / samples;
            fx = bx; fy = by; fz = bz;
            return;
        }
        fx += (x - fx) * 0.35;
        fy += (y - fy) * 0.35;
        fz += (z - fz) * 0.35;
        var dx = fx - bx;
        var dy = fy - by;
        var dz = fz - bz;
        var distanceSq = dx * dx + dy * dy + dz * dz;
        if (!away) {
            if (distanceSq > 67600) {
                away = true;
                departedAt = atMs;
                returnSince = -1;
            } else if (distanceSq < 22500) {
                bx += (fx - bx) * 0.002;
                by += (fy - by) * 0.002;
                bz += (fz - bz) * 0.002;
            }
        } else {
            if (distanceSq < 22500) {
                if (returnSince < 0) { returnSince = atMs; }
                if (atMs - returnSince >= 120) {
                    var duration = atMs - departedAt;
                    if (duration >= 450 && duration <= 5500 && atMs - lastRepAt >= 500) {
                        count += 1;
                        lastRepAt = atMs;
                    }
                    away = false;
                    returnSince = -1;
                }
            } else {
                returnSince = -1;
            }
            if (atMs - departedAt > 5500) {
                away = false;
                returnSince = -1;
                bx = fx; by = fy; bz = fz;
            }
        }
    }
}
