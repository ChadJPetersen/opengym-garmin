import Toybox.WatchUi;

class GymDelegate extends WatchUi.BehaviorDelegate {
    var controller;

    function initialize(model) {
        BehaviorDelegate.initialize();
        controller = model;
    }

    function onNextPage() {
        controller.moveSelection(1);
        return true;
    }

    function onPreviousPage() {
        controller.moveSelection(-1);
        return true;
    }

    function onSelect() {
        controller.selectAction();
        return true;
    }

    function onMenu() {
        controller.refresh();
        return true;
    }

    // Some button mappings dispatch raw keys instead of page/select behaviors.
    function onKey(event) {
        var key = event.getKey();
        if (key == WatchUi.KEY_DOWN) { controller.moveSelection(1); return true; }
        if (key == WatchUi.KEY_UP) { controller.moveSelection(-1); return true; }
        if (key == WatchUi.KEY_ENTER) { controller.selectAction(); return true; }
        if (key == WatchUi.KEY_MENU) { controller.refresh(); return true; }
        return false;
    }
}
