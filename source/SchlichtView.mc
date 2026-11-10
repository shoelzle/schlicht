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
    private const SUN_DISC_RADIUS = 8.4;
    private const SUN_RAY_FROM = 11.1;
    private const SUN_RAY_TO = 18.5;
    private const SUN_RAY_WIDTH = 5.75;
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
    //! Outer and inner edge of the heart outline in screen coordinates,
    //! built on the first draw (they only depend on font size and screen).
    private var _heartOuter as Array<[Numeric, Numeric]>? = null;
    private var _heartInner as Array<[Numeric, Numeric]>? = null;

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
            drawLowPower(dc, cx, cy, s, hourAngle, time.min * 6.0, time.min);
            return;
        }

        drawDial(dc, cx, cy, s);
        drawDayArc(dc, cx, cy, s, time.hour * 3600 + time.min * 60 + time.sec);
        drawDate(dc, cx + Layout.INFO_GAP * s, cy, s);
        drawHeartRate(dc, cx - Layout.INFO_GAP * s, cy, s);
        NotificationDots.draw(dc, cx, Layout.DOTS_FIRST_Y * s, s);

        var minuteAngle = (time.min + time.sec / 60.0) * 6.0;
        drawHourMinute(dc, cx, cy, s, hourAngle, minuteAngle);
        if (_showSeconds) {
            drawHand(dc, cx, cy, time.sec * 6.0, 204 * s, 34 * s, 1.84 * s, false);
        }
        drawHub(dc, cx, cy, s);
    }

    //! Hour and minute hand, shared by the normal and the always-on view.
    private function drawHourMinute(dc as Dc, cx as Float, cy as Float, s as Float,
            hourAngle as Float, minuteAngle as Float) as Void {
        drawHand(dc, cx, cy, hourAngle, 120 * s, 16 * s, 8.28 * s, true);
        drawHand(dc, cx, cy, minuteAngle, 198 * s, 16 * s, 5.18 * s, true);
    }

    //! White centre disc with a small black hole, on top of the hands.
    private function drawHub(dc as Dc, cx as Float, cy as Float, s as Float) as Void {
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
    //! size and the gap are exact; the disc is a polygon too (see fillDisc).
    private function drawSun(dc as Dc, x as Float, y as Float, s as Float) as Void {
        setFg(dc, SUN_YELLOW);
        fillDisc(dc, x, y, SUN_DISC_RADIUS * s);
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
        fillDisc(dc, x, y, 13.0 * s);
        setFg(dc, BLACK);
        fillDisc(dc, x + 6.2 * s, y - 4.6 * s, 11.0 * s);
    }

    //! A filled circle as a 32-sided polygon with an exact, fractional radius.
    //! fillCircle rounds the radius to whole pixels and draws the edge wider,
    //! which made the sun's disc almost touch its rays on the watch.
    private function fillDisc(dc as Dc, x as Float, y as Float, r as Float) as Void {
        var pts = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < 32; i++) {
            var deg = i * 11.25;
            pts.add([x + r * sinDeg(deg), y - r * cosDeg(deg)]);
        }
        dc.fillPolygon(pts);
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

        // The outline is a filled ring: the outer edge in grey, the inner edge
        // in black on top. Unlike drawLine segments (whole-pixel pen widths,
        // square ends) this gives a smooth, exactly 2.64 px wide line.
        var outer = _heartOuter;
        var inner = _heartInner;
        if (outer == null || inner == null) {
            outer = offsetHeart(k, 1.32 * s, heartX, cy);
            inner = offsetHeart(k, -1.32 * s, heartX, cy);
            _heartOuter = outer;
            _heartInner = inner;
        }
        dc.fillPolygon(outer);
        setFg(dc, BLACK);
        dc.fillPolygon(inner);
    }

    //! The heart curve scaled by k and moved outwards by d (inwards if d < 0),
    //! placed at (x0, y0). Each point moves along the bisector of its two edge
    //! normals (mitred, at most 1.6 x d). Points that would cross the vertical
    //! centre line (at the dip on top and the tip at the bottom) are dropped;
    //! each gap is closed with one point on the centre line.
    private function offsetHeart(k as Float, d as Float, x0 as Float, y0 as Float) as Array<[Numeric, Numeric]> {
        var n = _heart.size();
        var ox = [] as Array<Float>;
        var oy = [] as Array<Float>;
        var crossed = [] as Array<Boolean>;
        for (var i = 0; i < n; i++) {
            var p0 = _heart[(i + n - 1) % n];
            var p1 = _heart[i];
            var p2 = _heart[(i + 1) % n];
            // outward edge normals (the curve runs clockwise on screen)
            var ax = p1[0] - p0[0];
            var ay = p1[1] - p0[1];
            var la = Math.sqrt(ax * ax + ay * ay).toFloat();
            var nax = ay / la;
            var nay = -ax / la;
            var bx = p2[0] - p1[0];
            var by = p2[1] - p1[1];
            var lb = Math.sqrt(bx * bx + by * by).toFloat();
            var nbx = by / lb;
            var nby = -bx / lb;
            var mx = nax + nbx;
            var my = nay + nby;
            var lm = Math.sqrt(mx * mx + my * my).toFloat();
            mx = mx / lm;
            my = my / lm;
            var cosA = mx * nax + my * nay;
            if (cosA < 0.625) {
                cosA = 0.625;
            }
            var x = p1[0] * k + mx * d / cosA;
            ox.add(x);
            oy.add(p1[1] * k + my * d / cosA);
            crossed.add(p1[0] * x < 0);
        }
        var pts = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < n; i++) {
            if (crossed[i]) {
                continue;
            }
            pts.add([x0 + ox[i], y0 + oy[i]]);
            var j = (i + 1) % n;
            if (crossed[j]) {
                var t = ox[i] / (ox[i] - ox[j]);
                var y1 = oy[i] + t * (oy[j] - oy[i]);
                var m = j;
                while (crossed[m]) {
                    m = (m + 1) % n;
                }
                var q = (m + n - 1) % n;
                var t2 = ox[m] / (ox[m] - ox[q]);
                var y2 = oy[m] + t2 * (oy[q] - oy[m]);
                pts.add([x0, y0 + (y1 + y2) / 2]);
            }
        }
        return pts;
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

    //! Classic heart curve, sampled into 64 points, bounding box centred on 0/0
    //! (the raw curve spans y = -11.92 .. 17.0).
    private function buildHeart() as Array<[Float, Float]> {
        var pts = [] as Array<[Float, Float]>;
        for (var i = 0; i < 64; i++) {
            var t = i * 2 * Math.PI / 64;
            var x = 16 * Math.pow(Math.sin(t), 3);
            var y = -(13 * Math.cos(t) - 5 * Math.cos(2 * t) - 2 * Math.cos(3 * t) - Math.cos(4 * t));
            pts.add([x.toFloat(), (y - 2.54).toFloat()]);
        }
        return pts;
    }

    // ----------------------------------------------------------- low power

    //! Always-on (low power) mode on AMOLED screens: hour and minute hand
    //! (with centre disc) and the 12 hour dots, in the same size and place as
    //! in the normal view, nothing else.
    //!
    //! Garmin's burn-in rules: at most 10 % of the pixels lit and no pixel lit
    //! for more than 3 minutes. Full-width hands would keep their middle lit, so
    //! every third pixel row is blanked, and the blank rows move down by one row
    //! each minute. Every pixel is therefore dark at least one minute in three;
    //! the view looks slightly dimmed (two thirds of the pixels) and lights only
    //! about 2 % of the screen.
    private function drawLowPower(dc as Dc, cx as Float, cy as Float, s as Float,
            hourAngle as Float, minuteAngle as Float, minute as Number) as Void {
        var r = Layout.DIAL_DOT_RADIUS * s;
        setFg(dc, MAJOR_DOT_GREY);
        for (var h = 0; h < 12; h++) {
            var deg = h * 30.0;
            dc.fillCircle(cx + r * sinDeg(deg), cy - r * cosDeg(deg), 3.0 * s);
        }
        drawHourMinute(dc, cx, cy, s, hourAngle, minuteAngle);
        drawHub(dc, cx, cy, s);

        // blank every third row, exactly one pixel high (no anti-aliasing)
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
        setFg(dc, BLACK);
        dc.setPenWidth(1);
        var width = dc.getWidth();
        var height = dc.getHeight();
        for (var y = minute % 3; y < height; y += 3) {
            dc.drawLine(0, y, width, y);
        }
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
