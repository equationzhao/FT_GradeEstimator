import Toybox.Application;
import Toybox.WatchUi;

class GradeEstimatorApp extends Application.AppBase {
    var view as GradeEstimatorView or Null;

    function initialize() { AppBase.initialize(); }

    function onSettingsChanged() as Void {
        AppBase.onSettingsChanged();
        if (view != null) { view.updateSettings(); }
        WatchUi.requestUpdate();
    }

    function getInitialView() {
        view = new GradeEstimatorView();
        return [view];
    }
}
