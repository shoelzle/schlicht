import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

//! Long press on the notification dots opens the watch's notification list.
class SchlichtDelegate extends WatchUi.WatchFaceDelegate {

    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var width = System.getDeviceSettings().screenWidth;
        var s = width / Layout.DESIGN_SIZE;
        var cx = width / 2.0;
        if (NotificationDots.contains(xy[0], xy[1], cx, Layout.DOTS_FIRST_Y * s, s)) {
            try {
                Complications.exitTo(new Complications.Id(Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT));
                return true;
            } catch (e) {
                return false;
            }
        }
        return false;
    }
}
