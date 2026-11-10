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
        dc.drawText(cx, 39, Graphics.FONT_MEDIUM, controller.exercise, Graphics.TEXT_JUSTIFY_CENTER);
        var sets = "Set " + controller.setNumber.toString() + "/" + controller.setCount.toString();
        dc.drawText(cx, 71, Graphics.FONT_SMALL, sets, Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 94, Graphics.FONT_MEDIUM,
            controller.weight + " x " + controller.reps.toString(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x55FFAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 121, Graphics.FONT_MEDIUM, controller.heartText(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 148, Graphics.FONT_XTINY, controller.heartStats(), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, 165, Graphics.FONT_SMALL,
            "Rest " + controller.restSeconds.toString() + "s", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0x55FFAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 185, Graphics.FONT_SMALL,
            "> " + controller.selectedName() + " <", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, 204, Graphics.FONT_XTINY, controller.status, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
