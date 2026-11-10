import Toybox.Graphics;
import Toybox.WatchUi;

class GymView extends WatchUi.View {
    var controller;

    function initialize(model) {
        View.initialize();
        controller = model;
    }

    function onShow() {
        controller.refresh();
    }

    function onUpdate(dc) {
        var cx = dc.getWidth() / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0x55FFFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 8, Graphics.FONT_SMALL, "openGym", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 37, Graphics.FONT_MEDIUM, controller.exercise, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 67, Graphics.FONT_SMALL,
            "Set " + controller.setNumber.toString() + "/" + controller.setCount.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 92, Graphics.FONT_XTINY, "ESTIMATED / REQUIRED", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x55FFAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 104, Graphics.FONT_LARGE,
            controller.estimatedReps() + " / " + controller.reps.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 141, Graphics.FONT_SMALL, controller.heartText(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 164, Graphics.FONT_XTINY,
            "Rest " + controller.restSeconds.toString() + "s | " + controller.weight,
            Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x55FFAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 181, Graphics.FONT_MEDIUM,
            "> " + controller.selectedName() + " <", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 205, Graphics.FONT_XTINY, controller.status, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
