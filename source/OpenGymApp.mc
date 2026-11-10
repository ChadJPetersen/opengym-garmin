import Toybox.Application;
import Toybox.WatchUi;

class OpenGymApp extends Application.AppBase {
    var controller;

    function initialize() {
        AppBase.initialize();
        controller = new GymController();
    }

    function getInitialView() {
        return [ new GymView(controller), new GymDelegate(controller) ];
    }
}
