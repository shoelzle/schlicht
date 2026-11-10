import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Application entry point of the "Schlicht" watch face.
class SchlichtApp extends Application.AppBase {

    private var _view as SchlichtView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new SchlichtView();
        _view = view;
        return [view, new SchlichtDelegate()];
    }

    //! Called when the user changes settings in the Connect IQ app.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.loadSettings();
        }
        WatchUi.requestUpdate();
    }
}
