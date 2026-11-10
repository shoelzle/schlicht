import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

//! Unread phone notifications as a vertical column of small dots.
//!
//! One dot per unread notification, drawn upwards from a start point. Each dot
//! is darker than the one below it; the fifth one has faded to black, so from
//! four notifications on the column looks the same.
//!
//! Usage:
//!   NotificationDots.draw(dc, centerX, firstDotY, scale);
//!   if (NotificationDots.contains(x, y, centerX, firstDotY, scale)) { ... }
module NotificationDots {

    //! Highest number of dots drawn.
    const MAX_DOTS = 5;
    //! Grey value (0-255) of the first, brightest dot.
    const FIRST_GREY = 0x8a;
    //! Dot radius and distance between dots, in px on a 454 px screen.
    const RADIUS = 3.0;
    const STEP = 13.0;
    //! Extra margin around the dots for touch input, in px on a 454 px screen.
    const TOUCH_MARGIN = 20.0;

    //! Number of unread notifications, 0 if unknown.
    function count() as Number {
        var n = System.getDeviceSettings().notificationCount;
        return (n != null) ? n : 0;
    }

    //! Grey for dot k (0 = first). Fades linearly to black at dot MAX_DOTS - 1.
    function greyFor(k as Number) as Number {
        var v = Math.round(FIRST_GREY * (1.0 - k.toFloat() / (MAX_DOTS - 1))).toNumber();
        if (v < 0) {
            v = 0;
        }
        return (v << 16) | (v << 8) | v;
    }

    //! Draw the dots, starting at (cx, firstY) and going up.
    //! scale = screen width / 454.
    function draw(dc as Dc, cx as Numeric, firstY as Numeric, scale as Float) as Void {
        var n = count();
        if (n > MAX_DOTS) {
            n = MAX_DOTS;
        }
        for (var k = 0; k < n; k++) {
            var grey = greyFor(k);
            if (grey == 0) {
                continue;
            }
            dc.setColor(grey, Graphics.COLOR_TRANSPARENT);
            fillDot(dc, cx.toFloat(), (firstY - k * STEP * scale).toFloat(), (RADIUS * scale).toFloat());
        }
    }

    //! A dot as a 16-sided polygon with an exact radius. fillCircle draws
    //! dots about 1 px larger, which closes the gaps between them.
    function fillDot(dc as Dc, x as Float, y as Float, r as Float) as Void {
        var pts = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < 16; i++) {
            var a = i * Math.PI / 8;
            pts.add([x + r * Math.sin(a), y - r * Math.cos(a)]);
        }
        dc.fillPolygon(pts);
    }

    //! True if (x, y) hits the dot column (with a generous margin) while
    //! there is at least one unread notification.
    function contains(x as Numeric, y as Numeric, cx as Numeric, firstY as Numeric, scale as Float) as Boolean {
        var n = count();
        if (n == 0) {
            return false;
        }
        if (n > MAX_DOTS - 1) {
            n = MAX_DOTS - 1;    // the last dot is invisible
        }
        var margin = TOUCH_MARGIN * scale;
        var top = firstY - (n - 1) * STEP * scale - margin;
        var bottom = firstY + margin;
        return x >= cx - margin && x <= cx + margin && y >= top && y <= bottom;
    }
}
