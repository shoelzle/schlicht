import Toybox.Activity;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

//! A plain analog watch face: white on black, slim hands, grey dots at the edge.
//! Quietly in the background: day arc in weather colours with sun and moon,
//! date, heart rate and unread notifications (NotificationDots).
//!
//! All sizes are designed for a 454 px round screen (Venu 3) and scaled to the
//! actual screen size, so smaller round devices (e.g. Venu 3S, 390 px) work too.
//!
//! Colours are only ever set with setColor. The fill tool (setFill) is not
//! used: opaque white as ARGB is 0xFFFFFFFF = -1 = COLOR_TRANSPARENT.
class SchlichtView extends WatchUi.WatchFace {

    private const WHITE = 0xffffff;
    private const BLACK = 0x000000;
    private const MINOR_DOT_GREY = 0x8a8a8a;
    private const MAJOR_DOT_GREY = 0xa6a6a6;
    private const TEXT_GREY = 0xbdbdbd;       // sunrise/sunset times, moon
    private const INFO_GREY = 0xd6d6d6;       // heart, heart rate and date
    private const ARC_DAY = 0x4a4a4a;         // day arc without weather data
    private const SUN_YELLOW = 0xf5e050;      // sunrise marker, bright yellow
    // sun marker in px on a 454 px screen: disc, rays (base radius, tip radius, base width)
    private const SUN_DISC_RADIUS = 7.0;
    private const SUN_RAY_FROM = 8.8;
    private const SUN_RAY_TO = 15.0;
    private const SUN_RAY_WIDTH = 4.8;
    private const SOFT_EDGE_OUTER = 0x404040; // white at 25 % over black
    private const SOFT_EDGE_INNER = 0x808080; // white at 50 % over black

    private const HEART_HEIGHT = 28.92;       // height of the unit heart curve
    private const ROBOTO_CAP_PER_ASCENT = 0.767;   // cap height 0.711 em / ascent 0.927 em

    private const SECONDS_PER_DAY = 86400;
    private const SECONDS_PER_DIAL = 43200;   // 12 hours
    private const FADE_SECONDS = 3600;        // soft start of the day arc
    private const FADE_OUT_SECONDS = 1440;    // soft end at sunset: two minute dots (12 degrees)
    private const SPIRAL_FROM_SECONDS = 39600; // more than 11 h of daylight: spiral

    private var _awake as Boolean = true;
    private var _showSeconds as Boolean = true;

    private var _infoFont as FontType = Graphics.FONT_SMALL;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    private var _sunrise as Number? = null;
    private var _sunset as Number? = null;
    private var _sunCheckedAt as Number = -1;

    // Day arc geometry for the current frame (see radiusAt).
    private var _arcR0 as Float = 0.0;
    private var _arcGap as Float = 0.0;
    private var _arcT0 as Number = 0;
    private var _arcScale as Float = 1.0;

    //! Heart outline, unit size 32 x HEART_HEIGHT, centred on 0/0.
    private var _heart as Array<[Float, Float]> = [] as Array<[Float, Float]>;

    function initialize() {
        WatchFace.initialize();
        loadSettings();
        _heart = buildHeart();
    }

    function onLayout(dc as Dc) as Void {
        var s = dc.getWidth() / Layout.DESIGN_SIZE;
        // Fonts are calibrated by cap height (digit height), so text on the
        // watch is exactly as large as in the design.
        _infoFont = loadFontByCap(Layout.INFO_FONT_SIZE * s, Graphics.FONT_SMALL);
        _labelFont = loadFontByCap(25 * s, Graphics.FONT_TINY);
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
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        var hourAngle = ((time.hour % 12) + time.min / 60.0) * 30.0;

        if (!_awake) {
            setFg(dc, WHITE);
            drawLowPower(dc, cx, cy, s, hourAngle, time.min * 6.0, time.min);
            return;
        }

        drawDial(dc, cx, cy, s);
        drawDayArc(dc, cx, cy, s, time.hour * 3600 + time.min * 60 + time.sec);
        drawDate(dc, cx + Layout.INFO_GAP * s, cy, s);
        drawHeartRate(dc, cx - Layout.INFO_GAP * s, cy, s);
        NotificationDots.draw(dc, cx, Layout.DOTS_FIRST_Y * s, s);

        var minuteAngle = (time.min + time.sec / 60.0) * 6.0;
        drawHand(dc, cx, cy, hourAngle, 120 * s, 16 * s, 8.28 * s, true);
        drawHand(dc, cx, cy, minuteAngle, 198 * s, 16 * s, 5.18 * s, true);
        if (_showSeconds) {
            drawHand(dc, cx, cy, time.sec * 6.0, 204 * s, 34 * s, 1.84 * s, false);
        }
        setFg(dc, WHITE);
        dc.fillCircle(cx, cy, 6 * s);
        setFg(dc, BLACK);
        dc.fillCircle(cx, cy, 2 * s);
    }

    // ---------------------------------------------------------------- dial

    //! 60 grey dots near the edge; every fifth one is larger and a little lighter
    //! (same size as the notification dots).
    private function drawDial(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
        var r = Layout.DIAL_DOT_RADIUS * s;
        for (var i = 0; i < 60; i++) {
            var major = (i % 5 == 0);
            setFg(dc, major ? MAJOR_DOT_GREY : MINOR_DOT_GREY);
            var deg = i * 6.0;
            dc.fillCircle(cx + r * sinDeg(deg), cy - r * cosDeg(deg), (major ? 3.0 : 1.6) * s);
        }
    }

    //! A white hand with rounded ends. Angle in degrees, clockwise from 12.
    //! With soft = true, two slightly wider grey layers underneath give it a
    //! soft edge (white at 25 % and 50 % over the black background).
    private function drawHand(dc as Dc, cx as Float, cy as Float, deg as Float,
            length as Float, tail as Float, width as Float, soft as Boolean) as Void {
        if (soft) {
            setFg(dc, SOFT_EDGE_OUTER);
            fillHand(dc, cx, cy, deg, length, tail, width + 2.0);
            setFg(dc, SOFT_EDGE_INNER);
            fillHand(dc, cx, cy, deg, length, tail, width + 1.0);
        }
        setFg(dc, WHITE);
        fillHand(dc, cx, cy, deg, length, tail, width);
    }

    //! Filled bar with round ends as ONE polygon. The tip is a fine half
    //! circle (13 points, 15° steps), the tail a coarser one (7 points). fillCircle would round its centre and radius to whole
    //! pixels and leave small bumps at the ends of fractional-width hands.
    private function fillHand(dc as Dc, cx as Float, cy as Float, deg as Float,
            length as Float, tail as Float, width as Float) as Void {
        var sin = sinDeg(deg);
        var cos = cosDeg(deg);
        var half = width / 2;
        var tipX = cx + length * sin;
        var tipY = cy - length * cos;
        var tailX = cx - tail * sin;
        var tailY = cy + tail * cos;
        var pts = [] as Array<Point2D>;
        // tip cap: from the left side over the tip to the right side
        for (var i = 0; i <= 12; i++) {
            var a = deg - 90.0 + i * 15.0;
            pts.add([tipX + half * sinDeg(a), tipY - half * cosDeg(a)]);
        }
        // tail cap: from the right side over the tail end to the left side
        for (var i = 0; i <= 6; i++) {
            var a = deg + 90.0 + i * 30.0;
            pts.add([tailX + half * sinDeg(a), tailY - half * cosDeg(a)]);
        }
        dc.fillPolygon(pts);
    }

    // ------------------------------------------------------------- day arc

    //! Remaining daylight as a fine arc from the hour hand's position to sunset,
    //! coloured by the hourly weather forecast (see WeatherArc); hidden at night.
    //! Sunrise and sunset are marked with a small sun and moon and their times.
    //! Nothing is drawn when the times are unknown.
    private function drawDayArc(dc as Dc, cx as Float, cy as Float, s as Float, now as Number) as Void {
        updateSunTimes(now);
        var sunrise = _sunrise;
        var sunset = _sunset;
        if (sunrise == null || sunset == null) {
            return;
        }

        // Long days become a spiral: later = further in, so the end of the arc
        // never overlaps its start (ADR-004).
        _arcR0 = Layout.ARC_RADIUS * s;
        _arcT0 = sunrise;
        _arcGap = (sunset - sunrise > SPIRAL_FROM_SECONDS) ? Layout.SPIRAL_GAP * s : 0.0;
        _arcScale = s;

        if (now >= sunrise && now < sunset && sunset - now >= 60) {
            WeatherArc.update(now, sunset);
            // fade in over the last hour before the hour hand, in the colour of "now"
            var fadeFrom = now - FADE_SECONDS;
            if (fadeFrom < sunrise) {
                fadeFrom = sunrise;
            }
            var nowColor = WeatherArc.hasData() ? WeatherArc.colorAt(now) : ARC_DAY;
            drawFadeIn(dc, cx, cy, fadeFrom, now, nowColor);
            drawWeatherArc(dc, cx, cy, now, sunset);
        }

        var riseDeg = dialDegrees(sunrise);
        var setDeg = dialDegrees(sunset);
        var riseR = radiusAt(sunrise);
        var setR = radiusAt(sunset);
        drawSun(dc, cx + riseR * sinDeg(riseDeg), cy - riseR * cosDeg(riseDeg), s);
        drawMoon(dc, cx + setR * sinDeg(setDeg), cy - setR * cosDeg(setDeg), s);

        setFg(dc, TEXT_GREY);
        var labelIn = (Layout.ARC_RADIUS - Layout.ARC_LABEL_RADIUS) * s;
        var a = riseDeg - Layout.ARC_LABEL_OFFSET_DEG;
        var lr = riseR - labelIn;
        drawCentered(dc, cx + lr * sinDeg(a), cy - lr * cosDeg(a), _labelFont, formatTime(sunrise));
        a = setDeg + Layout.ARC_LABEL_OFFSET_DEG;
        lr = setR - labelIn;
        drawCentered(dc, cx + lr * sinDeg(a), cy - lr * cosDeg(a), _labelFont, formatTime(sunset));
    }

    //! Radius of the day arc at a time of day: constant on short days, moving
    //! inwards by SPIRAL_GAP per 12 hours on long days.
    private function radiusAt(t as Number) as Float {
        return _arcR0 - _arcGap * (t - _arcT0) / SECONDS_PER_DIAL.toFloat();
    }

    //! Day arc from "from" to sunset in forecast colours (grey without weather
    //! data), in 2-degree (4-minute) pieces. The last FADE_OUT_SECONDS fade to
    //! black, so the arc dissolves into the moon.
    private function drawWeatherArc(dc as Dc, cx as Float, cy as Float, from as Number, to as Number) as Void {
        var weather = WeatherArc.hasData();
        var fadeStart = to - FADE_OUT_SECONDS;
        var t = from;
        while (t < to) {
            // finer 1-degree pieces where the arc fades out
            var t2 = t + ((t >= fadeStart) ? 120 : 240);
            if (t2 > to) {
                t2 = to;
            }
            // drawArc takes whole degrees; equal start and end would draw a full circle
            var a1 = arcDegree(t);
            var a2 = arcDegree(t2);
            if (a1 != a2) {
                var mid = (t + t2) / 2;
                var color = weather ? WeatherArc.colorAt(mid) : ARC_DAY;
                if (mid > fadeStart) {
                    var f = (mid - fadeStart).toFloat() / FADE_OUT_SECONDS;
                    color = WeatherArc.mix(color, BLACK, f * f * (3 - 2 * f));
                }
                arcPiece(dc, cx, cy, radiusAt(mid), a1, a2, color);
            }
            t = t2;
        }
    }

    //! Soft start of the day arc: from black to the given colour between
    //! "from" and "to" (the hour hand), in 2-degree pieces.
    private function drawFadeIn(dc as Dc, cx as Float, cy as Float,
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
                var mid = (t + t2) / 2;
                var f = (mid - from).toFloat() / span;
                arcPiece(dc, cx, cy, radiusAt(mid), a1, a2, WeatherArc.mix(BLACK, color, f * f * (3 - 2 * f)));
            }
            t = t2;
        }
    }

    //! One piece of the day arc, 2.5 px wide: setPenWidth only takes whole
    //! pixels, so a 2 px line is followed by a 1 px line at half brightness
    //! just outside it.
    private function arcPiece(dc as Dc, cx as Float, cy as Float, r as Float,
            a1 as Number, a2 as Number, color as Number) as Void {
        var s = _arcScale;
        setFg(dc, color);
        setPen(dc, 2.0 * s);
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, a1, a2);
        setFg(dc, WeatherArc.mix(BLACK, color, 0.5));
        setPen(dc, 1.0 * s);
        dc.drawArc(cx, cy, r + 1.5 * s, Graphics.ARC_CLOCKWISE, a1, a2);
    }

    //! Sunrise marker: a small, slightly yellow sun – a disc and eight
    //! triangular rays with a clear gap in between. Rays are polygons, so their
    //! size and the gap are exact (fillCircle only rounds the disc).
    private function drawSun(dc as Dc, x as Float, y as Float, s as Float) as Void {
        setFg(dc, SUN_YELLOW);
        dc.fillCircle(x, y, SUN_DISC_RADIUS * s);
        for (var i = 0; i < 8; i++) {
            fillRay(dc, x, y, i * 45.0, SUN_RAY_FROM * s, SUN_RAY_TO * s, SUN_RAY_WIDTH * s);
        }
    }

    //! A triangle pointing outwards: base of the given width at radius r1,
    //! tip at radius r2 around (x, y).
    private function fillRay(dc as Dc, x as Float, y as Float, deg as Float,
            r1 as Float, r2 as Float, width as Float) as Void {
        var sin = sinDeg(deg);
        var cos = cosDeg(deg);
        var px = width / 2 * cos;
        var py = width / 2 * sin;
        var x1 = x + r1 * sin;
        var y1 = y - r1 * cos;
        dc.fillPolygon([[x1 - px, y1 - py], [x1 + px, y1 + py], [x + r2 * sin, y - r2 * cos]]);
    }

    //! Sunset marker: a small crescent moon (a disc with a black disc cut out).
    private function drawMoon(dc as Dc, x as Float, y as Float, s as Float) as Void {
        setFg(dc, TEXT_GREY);
        dc.fillCircle(x, y, 13.0 * s);
        setFg(dc, BLACK);
        dc.fillCircle(x + 6.2 * s, y - 4.6 * s, 11.0 * s);
    }

    //! Sunrise and sunset in seconds since local midnight, refreshed every
    //! 10 minutes. First choice: Weather.getSunrise/getSunset for the weather
    //! location (real moments, so the time zone is always right). Fallback:
    //! the native sunrise/sunset complications.
    private function updateSunTimes(now as Number) as Void {
        if (_sunCheckedAt >= 0 && now >= _sunCheckedAt && now - _sunCheckedAt < 600) {
            return;
        }
        _sunCheckedAt = now;
        _sunrise = weatherSunTime(true);
        _sunset = weatherSunTime(false);
        if (_sunrise == null || _sunset == null) {
            _sunrise = complicationNumber(Complications.COMPLICATION_TYPE_SUNRISE);
            _sunset = complicationNumber(Complications.COMPLICATION_TYPE_SUNSET);
        }
    }

    private function weatherSunTime(rise as Boolean) as Number? {
        if (!(Toybox has :Weather) || !(Weather has :getSunrise)) {
            return null;
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return null;
        }
        var location = conditions.observationLocationPosition;
        if (location == null) {
            return null;
        }
        var today = Time.now();
        var moment = rise ? Weather.getSunrise(location, today) : Weather.getSunset(location, today);
        if (moment == null) {
            return null;
        }
        var t = moment.value() - Time.today().value();
        return ((t % SECONDS_PER_DAY) + SECONDS_PER_DAY) % SECONDS_PER_DAY;
    }

    //! Position on the 12-hour dial in degrees, clockwise from 12.
    private function dialDegrees(secondsOfDay as Number) as Float {
        return (secondsOfDay % SECONDS_PER_DIAL) * 360.0 / SECONDS_PER_DIAL;
    }

    //! Time of day as a whole drawArc angle (0 = 3 o'clock, counter-clockwise).
    private function arcDegree(secondsOfDay as Number) as Number {
        var a = (90 - dialDegrees(secondsOfDay)).toNumber();
        return a < 0 ? a + 360 : a;
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
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var text = info.day_of_week + " " + info.day;
        setFg(dc, INFO_GREY);
        dc.drawText(x, textTop(cy, _infoFont), _infoFont, text, Graphics.TEXT_JUSTIFY_LEFT);
    }

    //! Heart outline, exactly as tall as the date digits, its right edge at
    //! rightX. While a live heart rate is available, the number stands to the
    //! left of the heart, in the date's font.
    private function drawHeartRate(dc as Dc, rightX as Float, cy as Float, s as Float) as Void {
        var k = capHeight(_infoFont) / HEART_HEIGHT;
        var heartWidth = 32.0 * k;
        var heartX = rightX - heartWidth / 2;

        setFg(dc, INFO_GREY);
        var hr = Activity.getActivityInfo().currentHeartRate;
        if (hr != null && hr > 0) {
            dc.drawText(rightX - heartWidth - 7 * s, textTop(cy, _infoFont), _infoFont,
                hr.toString(), Graphics.TEXT_JUSTIFY_RIGHT);
        }

        setPen(dc, 2.64 * s);
        var n = _heart.size();
        for (var i = 0; i < n; i++) {
            var p = _heart[i];
            var q = _heart[(i + 1) % n];
            dc.drawLine(heartX + p[0] * k, cy + p[1] * k, heartX + q[0] * k, cy + q[1] * k);
        }
    }

    //! Height of capital letters and digits, derived from the font's ascent
    //! (Roboto: cap 0.711 em, ascent 0.927 em). This works whatever the font
    //! size means on the device.
    private function capHeight(font as FontType) as Float {
        return Graphics.getFontAscent(font) * ROBOTO_CAP_PER_ASCENT;
    }

    //! Top y for drawText (without VCENTER) so that the digits are centred on
    //! cy: baseline = cy + cap / 2, top = baseline - ascent.
    private function textTop(cy as Float, font as FontType) as Float {
        return cy + capHeight(font) / 2 - Graphics.getFontAscent(font);
    }

    //! Classic heart curve, sampled into 32 points, bounding box centred on 0/0
    //! (the raw curve spans y = -11.92 .. 17.0).
    private function buildHeart() as Array<[Float, Float]> {
        var pts = [] as Array<[Float, Float]>;
        for (var i = 0; i < 32; i++) {
            var t = i * 2 * Math.PI / 32;
            var x = 16 * Math.pow(Math.sin(t), 3);
            var y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
            pts.add([x.toFloat(), (y - 2.54).toFloat()]);
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

        var r = Layout.DIAL_DOT_RADIUS * s;
        for (var h = 0; h < 12; h++) {
            var deg = h * 30.0;
            dc.fillCircle(x0 + r * sinDeg(deg), y0 - r * cosDeg(deg), 3);
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

    //! Scalable font whose digits are as tall as Roboto at `size` px in the
    //! design (cap height 0.711 em). What getVectorFont's :size means can
    //! differ per device, so the font is measured once and loaded again with
    //! a corrected size.
    private function loadFontByCap(size as Float, fallback as FontType) as FontType {
        var font = loadFont(size, fallback);
        if (font == fallback) {
            return font;
        }
        var wanted = size * 0.711;
        var actual = capHeight(font);
        if (actual > 0 && (actual - wanted).abs() > 0.5) {
            font = loadFont(size * wanted / actual, fallback);
        }
        return font;
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

    //! The only place colours are set (see class comment).
    private function setFg(dc as Dc, rgb as Number) as Void {
        dc.setColor(rgb, Graphics.COLOR_TRANSPARENT);
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
