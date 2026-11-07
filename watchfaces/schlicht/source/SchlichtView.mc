import Toybox.Activity;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! A plain analog watch face: white on black, slim hands, grey dots at the edge.
//! Quietly in the background: day arc with sunrise/sunset, date, heart rate
//! and unread notifications (NotificationDots barrel).
//!
//! All sizes are designed for a 454 px round screen (Venu 3) and scaled to the
//! actual screen size, so smaller round devices (e.g. Venu 3S, 390 px) work too.
class SchlichtView extends WatchUi.WatchFace {

    private const WHITE = 0xffffff;
    private const BLACK = 0x000000;
    private const MINOR_DOT_GREY = 0x8a8a8a;
    private const MAJOR_DOT_GREY = 0xa6a6a6;
    private const TEXT_GREY = 0xbdbdbd;
    private const INFO_GREY = 0xd6d6d6;   // heart, heart rate and date
    private const ARC_DAY = 0x4a4a4a;
    private const ARC_NIGHT = 0x2e2e2e;
    private const SUN_YELLOW = 0xd4c27e;   // sunrise marker
    private const HEART_HEIGHT = 28.92;   // height of the unit heart curve

    private const SECONDS_PER_DAY = 86400;
    private const SECONDS_PER_DIAL = 43200;   // 12 hours
    private const FADE_SECONDS = 3600;        // soft start of the day arc
    private const FADE_OUT_SECONDS = 1440;    // soft end at sunset: two minute dots (12 degrees)

    private var _awake as Boolean = true;
    private var _showSeconds as Boolean = true;

    private var _dateFont as FontType = Graphics.FONT_SMALL;
    private var _valueFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    //! Heart outline, unit size 32 x HEART_HEIGHT, centred on 0/0.
    private var _heart as Array<[Float, Float]> = [] as Array<[Float, Float]>;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
        _heart = buildHeart();
    }

    function onLayout(dc as Dc) as Void {
        var s = dc.getWidth() / Layout.DESIGN_SIZE;
        _dateFont = loadFont(Layout.INFO_FONT_SIZE * s, Graphics.FONT_SMALL);
        _valueFont = _dateFont;
        _labelFont = loadFont(19 * s, Graphics.FONT_XTINY);
    }

    //! Read the user settings (Connect IQ app → watch face → Settings).
    function loadSettings() as Void {
        var seconds = Application.Properties.getValue("ShowSeconds");
        if (seconds instanceof Boolean) {
            _showSeconds = seconds;
        } else {
            _showSeconds = true;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var s = dc.getWidth() / Layout.DESIGN_SIZE;
        var cx = dc.getWidth() / 2.0;
        var cy = dc.getHeight() / 2.0;
        var time = System.getClockTime();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        setFg(dc, WHITE);
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var hourAngle = ((time.hour % 12) + time.min / 60.0) * 30.0;

        if (!_awake) {
            setFg(dc, WHITE);
            drawLowPower(dc, cx, cy, s, hourAngle, time.min * 6.0, time.min);
            return;
        }

        drawTicks(dc, cx, cy, s);
        drawDayArc(dc, cx, cy, s, time.hour * 3600 + time.min * 60 + time.sec);
        drawDate(dc, cx + Layout.INFO_GAP * s, cy, s);
        drawHeartRate(dc, cx - Layout.INFO_GAP * s, cy, s);
        NotificationDots.draw(dc, cx, Layout.DOTS_FIRST_Y * s, s);

        var minuteAngle = (time.min + time.sec / 60.0) * 6.0;
        drawHand(dc, cx, cy, hourAngle, 120 * s, 16 * s, 7.2 * s, true);
        drawHand(dc, cx, cy, minuteAngle, 198 * s, 16 * s, 4.5 * s, true);
        if (_showSeconds) {
            drawHand(dc, cx, cy, time.sec * 6.0, 204 * s, 34 * s, 1.6 * s, false);
        }
        setFg(dc, WHITE);
        dc.fillCircle(cx, cy, 6 * s);
        setFg(dc, BLACK);
        dc.fillCircle(cx, cy, 2 * s);
    }

    // ---------------------------------------------------------------- dial

    //! 60 grey dots near the edge; every fifth one is larger and a little lighter
    //! (same size as the notification dots).
    private function drawTicks(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
        var r = Layout.DIAL_DOT_RADIUS * s;
        for (var i = 0; i < 60; i++) {
            var major = (i % 5 == 0);
            setFg(dc, major ? MAJOR_DOT_GREY : MINOR_DOT_GREY);
            var deg = i * 6.0;
            dc.fillCircle(cx + r * sinDeg(deg), cy - r * cosDeg(deg), (major ? 3.0 : 1.6) * s);
        }
    }

    //! A white hand with rounded ends. Angle in degrees, clockwise from 12.
    //! With soft = true, two translucent, slightly wider layers underneath give
    //! it a soft edge (on devices with alpha blending).
    private function drawHand(dc as Dc, cx as Float, cy as Float, deg as Float,
            length as Float, tail as Float, width as Float, soft as Boolean) as Void {
        if (soft && (dc has :setFill)) {
            dc.setFill((0x40 << 24) | WHITE);   // 25 %
            fillHand(dc, cx, cy, deg, length, tail, width + 2.0);
            dc.setFill((0x80 << 24) | WHITE);   // 50 %
            fillHand(dc, cx, cy, deg, length, tail, width + 1.0);
        }
        setFg(dc, WHITE);
        fillHand(dc, cx, cy, deg, length, tail, width);
    }

    //! Filled bar with round ends, drawn as a polygon so that fractional
    //! widths work with anti-aliasing.
    private function fillHand(dc as Dc, cx as Float, cy as Float, deg as Float,
            length as Float, tail as Float, width as Float) as Void {
        var rad = Math.toRadians(deg);
        var sin = Math.sin(rad);
        var cos = Math.cos(rad);
        var x1 = cx - tail * sin;
        var y1 = cy + tail * cos;
        var x2 = cx + length * sin;
        var y2 = cy - length * cos;
        var px = width / 2 * cos;
        var py = width / 2 * sin;
        dc.fillPolygon([[x1 - px, y1 - py], [x1 + px, y1 + py], [x2 + px, y2 + py], [x2 - px, y2 - py]]);
        dc.fillCircle(x1, y1, width / 2);
        dc.fillCircle(x2, y2, width / 2);
    }

    // ------------------------------------------------------------- day arc

    //! Remaining daylight as a fine arc from the hour hand's position to sunset,
    //! coloured by the hourly weather forecast (see WeatherArc)
    //! (at night: a darker arc to the next sunrise). Sunrise and sunset are
    //! marked with a dot and their time. Hidden when the times are unknown.
    private function drawDayArc(dc as Dc, cx as Float, cy as Float, s as Float, now as Number) as Void {
        var sunrise = complicationNumber(Complications.COMPLICATION_TYPE_SUNRISE);
        var sunset = complicationNumber(Complications.COMPLICATION_TYPE_SUNSET);
        if (sunrise == null || sunset == null) {
            return;
        }

        var target;
        var night = true;
        if (now < sunrise) {
            target = sunrise;
        } else if (now < sunset) {
            target = sunset;
            night = false;
        } else {
            target = sunrise + SECONDS_PER_DAY;   // tomorrow, about the same time
        }
        var remaining = target - now;
        if (remaining > SECONDS_PER_DIAL - 60) {
            remaining = SECONDS_PER_DIAL - 60;    // never more than one turn
        }

        var r = Layout.ARC_RADIUS * s;
        if (remaining >= 60) {
            setPen(dc, 2 * s);
            if (!night) {
                WeatherArc.update(now, sunset);
            }
            if (!night) {
                // fade in over the last hour before the hour hand, in the colour of "now"
                var fadeFrom = now - FADE_SECONDS;
                if (fadeFrom < sunrise) {
                    fadeFrom = sunrise;
                }
                var nowColor = WeatherArc.hasData() ? WeatherArc.colorAt(now) : ARC_DAY;
                drawFadeIn(dc, cx, cy, r, fadeFrom, now, nowColor);
            }
            if (!night) {
                drawWeatherArc(dc, cx, cy, r, now, now + remaining, now + remaining == sunset);
            } else {
                setFg(dc, night ? ARC_NIGHT : ARC_DAY);
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE,
                    90 - dialDegrees(now), 90 - dialDegrees(now + remaining));
            }
        }

        var riseDeg = dialDegrees(sunrise);
        var setDeg = dialDegrees(sunset);
        drawSun(dc, cx + r * sinDeg(riseDeg), cy - r * cosDeg(riseDeg), s);
        drawMoon(dc, cx + r * sinDeg(setDeg), cy - r * cosDeg(setDeg), s);
        setFg(dc, TEXT_GREY);

        var lr = Layout.ARC_LABEL_RADIUS * s;
        var a = riseDeg - Layout.ARC_LABEL_OFFSET_DEG;
        drawCentered(dc, cx + lr * sinDeg(a), cy - lr * cosDeg(a), _labelFont, formatTime(sunrise));
        a = setDeg + Layout.ARC_LABEL_OFFSET_DEG;
        drawCentered(dc, cx + lr * sinDeg(a), cy - lr * cosDeg(a), _labelFont, formatTime(sunset));
    }

    //! Day arc in forecast colours (grey without weather data), drawn in
    //! 2-degree (4-minute) pieces. With fadeOut, the last FADE_OUT_SECONDS
    //! fade to black, so the arc dissolves into the moon at sunset.
    private function drawWeatherArc(dc as Dc, cx as Float, cy as Float, r as Float,
            from as Number, to as Number, fadeOut as Boolean) as Void {
        var weather = WeatherArc.hasData();
        var fadeStart = to - FADE_OUT_SECONDS;
        var step = 240;
        var t = from;
        while (t < to) {
            // finer 1-degree pieces where the arc fades out
            var t2 = t + ((fadeOut && t >= fadeStart) ? 120 : step);
            if (t2 > to) {
                t2 = to;
            }
            // drawArc takes whole degrees; equal start and end would draw a full circle
            var a1 = arcDegree(t);
            var a2 = arcDegree(t2);
            if (a1 != a2) {
                var mid = (t + t2) / 2;
                var color = weather ? WeatherArc.colorAt(mid) : ARC_DAY;
                if (fadeOut && mid > fadeStart) {
                    var f = (mid - fadeStart).toFloat() / FADE_OUT_SECONDS;
                    f = f * f * (3 - 2 * f);   // smooth step
                    color = WeatherArc.mix(color, BLACK, f);
                }
                setFg(dc, color);
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a1, a2);
            }
            t = t2;
        }
    }

    //! Soft start of the day arc: from black to the given colour between
    //! "from" and "to" (the hour hand), in 2-degree pieces.
    private function drawFadeIn(dc as Dc, cx as Float, cy as Float, r as Float,
            from as Number, to as Number, color as Number) as Void {
        var span = to - from;
        if (span < 240) {
            return;
        }
        var t = from;
        while (t < to) {
            var t2 = t + 240;
            if (t2 > to) {
                t2 = to;
            }
            var a1 = arcDegree(t);
            var a2 = arcDegree(t2);
            if (a1 != a2) {
                var f = ((t + t2) / 2 - from).toFloat() / span;
                f = f * f * (3 - 2 * f);   // smooth step
                setFg(dc, WeatherArc.mix(BLACK, color, f));
                dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a1, a2);
            }
            t = t2;
        }
    }

    //! Time of day as a whole drawArc angle (0 = 3 o'clock, counter-clockwise).
    private function arcDegree(secondsOfDay as Number) as Number {
        var a = (90 - dialDegrees(secondsOfDay)).toNumber();
        return a < 0 ? a + 360 : a;
    }

    //! Sunrise marker: a small, slightly yellow sun: a disc with eight short rays.
    private function drawSun(dc as Dc, x as Float, y as Float, s as Float) as Void {
        setFg(dc, SUN_YELLOW);
        dc.fillCircle(x, y, 3.0 * s);
        setPen(dc, 1.5 * s);
        for (var i = 0; i < 8; i++) {
            var deg = i * 45.0;
            var sn = sinDeg(deg);
            var cs = cosDeg(deg);
            dc.drawLine(x + 5.0 * s * sn, y - 5.0 * s * cs, x + 7.5 * s * sn, y - 7.5 * s * cs);
        }
    }

    //! Sunset marker: a small crescent moon (a disc with a black disc cut out).
    private function drawMoon(dc as Dc, x as Float, y as Float, s as Float) as Void {
        setFg(dc, TEXT_GREY);
        dc.fillCircle(x, y, 6.5 * s);
        setFg(dc, BLACK);
        dc.fillCircle(x + 3.1 * s, y - 2.3 * s, 5.5 * s);
    }

    //! Position on the 12-hour dial in degrees, clockwise from 12.
    private function dialDegrees(secondsOfDay as Number) as Float {
        return (secondsOfDay % SECONDS_PER_DIAL) * 360.0 / SECONDS_PER_DIAL;
    }

    //! "07:28" or "7:28", following the watch's 12/24-hour setting.
    private function formatTime(secondsOfDay as Number) as String {
        var h = (secondsOfDay / 3600) % 24;
        var m = (secondsOfDay / 60) % 60;
        if (System.getDeviceSettings().is24Hour) {
            return h.format("%02d") + ":" + m.format("%02d");
        }
        h = h % 12;
        if (h == 0) {
            h = 12;
        }
        return h.toString() + ":" + m.format("%02d");
    }

    // ---------------------------------------------------------- date, heart

    //! "Sa 7", in the watch's language. Starts at x; the digits are vertically
    //! centred on cy, exactly like the heart on the other side.
    private function drawDate(dc as Dc, x as Float, cy as Float, s as Float) as Void {
        var text = null;
        try {
            var c = Complications.getComplication(new Complications.Id(Complications.COMPLICATION_TYPE_WEEKDAY_MONTHDAY));
            text = c.value;
        } catch (e) {
            text = null;
        }
        if (!(text instanceof String)) {
            var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            text = info.day_of_week + " " + info.day;
        }
        setFg(dc, INFO_GREY);
        dc.drawText(x, capCenterY(cy, _dateFont, s), _dateFont, text as String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Heart outline, exactly as tall as the date digits, its right edge at
    //! rightX. While a live heart rate is available, the number stands to the
    //! left of the heart, in the date's font.
    private function drawHeartRate(dc as Dc, rightX as Float, cy as Float, s as Float) as Void {
        var height = Layout.INFO_FONT_SIZE * Layout.CAP_HEIGHT * s;
        var k = height / HEART_HEIGHT;
        var heartWidth = 32.0 * k;
        var heartX = rightX - heartWidth / 2;

        var hr = Activity.getActivityInfo().currentHeartRate;
        if (hr != null && hr > 0) {
            setFg(dc, INFO_GREY);
            dc.drawText(rightX - heartWidth - 7 * s, capCenterY(cy, _valueFont, s), _valueFont,
                hr.toString(), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        setFg(dc, INFO_GREY);
        setPen(dc, 2.2 * s);
        var n = _heart.size();
        for (var i = 0; i < n; i++) {
            var p = _heart[i];
            var q = _heart[(i + 1) % n];
            dc.drawLine(heartX + p[0] * k, cy + p[1] * k, heartX + q[0] * k, cy + q[1] * k);
        }
    }

    //! y for drawText(..., TEXT_JUSTIFY_VCENTER) so that the digits (cap
    //! height), not the whole font box, are centred on cy.
    private function capCenterY(cy as Float, font as FontType, s as Float) as Float {
        var ascent = Graphics.getFontAscent(font);
        var descent = Graphics.getFontDescent(font);
        var cap = Layout.INFO_FONT_SIZE * Layout.CAP_HEIGHT * s;
        return cy + cap / 2 - (ascent - descent) / 2.0;
    }

    //! Classic heart curve, sampled into 32 points.
    private function buildHeart() as Array<[Float, Float]> {
        var pts = [] as Array<[Float, Float]>;
        for (var i = 0; i < 32; i++) {
            var t = i * 2 * Math.PI / 32;
            var x = 16 * Math.pow(Math.sin(t), 3);
            var y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
            pts.add([x.toFloat(), (y - 2.54).toFloat()]);   // centre the bounding box on 0
        }
        return pts;
    }

    // ----------------------------------------------------------- low power

    //! Always-on (low power) mode on AMOLED screens.
    //!
    //! Garmin's burn-in rules: at most 10 % of the pixels lit and no pixel lit for
    //! more than 3 minutes. We therefore draw only thin hands and 12 small dots and
    //! shift everything by 4 px in a 4-minute cycle (right, down, left, up). Within
    //! any 3 consecutive minutes no pixel of a 2 px line or a 3 px dot stays lit.
    private function drawLowPower(dc as Dc, cx as Float, cy as Float, s as Float,
            hourAngle as Float, minuteAngle as Float, minute as Number) as Void {
        var dx = [4, 0, -4, 0] as Array<Number>;
        var dy = [0, 4, 0, -4] as Array<Number>;
        var i = minute % 4;
        var x0 = cx + dx[i];
        var y0 = cy + dy[i];

        for (var h = 0; h < 12; h++) {
            var deg = h * 30.0;
            dc.fillCircle(x0 + Layout.DIAL_DOT_RADIUS * s * sinDeg(deg), y0 - Layout.DIAL_DOT_RADIUS * s * cosDeg(deg), 3);
        }
        dc.setPenWidth(2);
        drawLine(dc, x0, y0, hourAngle, 120 * s);
        drawLine(dc, x0, y0, minuteAngle, 198 * s);
    }

    private function drawLine(dc as Dc, cx as Float, cy as Float, deg as Float, length as Float) as Void {
        dc.drawLine(cx, cy, cx + length * sinDeg(deg), cy - length * cosDeg(deg));
    }

    // ------------------------------------------------------------- helpers

    //! Value of a native complication as a Number, or null.
    private function complicationNumber(type as Complications.Type) as Number? {
        try {
            var value = Complications.getComplication(new Complications.Id(type)).value;
            if (value instanceof Number) {
                return value;
            }
        } catch (e) {
            // not available on this device
        }
        return null;
    }

    //! Scalable Roboto font of the given pixel size, or a fallback system font.
    private function loadFont(size as Float, fallback as FontType) as FontType {
        if (Graphics has :getVectorFont) {
            var font = Graphics.getVectorFont({
                :face => ["RobotoRegular", "RobotoCondensedRegular"],
                :size => Math.round(size).toNumber()
            });
            if (font != null) {
                return font;
            }
        }
        return fallback;
    }

    private function drawCentered(dc as Dc, x as Float, y as Float, font as FontType, text as String) as Void {
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Set the colour for text, lines and fills. On newer devices the fill tool
    //! (setFill) takes precedence over setColor, so both are set.
    private function setFg(dc as Dc, rgb as Number) as Void {
        dc.setColor(rgb, Graphics.COLOR_TRANSPARENT);
        if (dc has :setFill) {
            dc.setFill((0xff << 24) | rgb);
        }
    }

    private function setPen(dc as Dc, width as Float) as Void {
        var pen = Math.round(width).toNumber();
        dc.setPenWidth(pen < 1 ? 1 : pen);
    }

    private function sinDeg(deg as Float) as Float {
        return Math.sin(Math.toRadians(deg)).toFloat();
    }

    private function cosDeg(deg as Float) as Float {
        return Math.cos(Math.toRadians(deg)).toFloat();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }
}
