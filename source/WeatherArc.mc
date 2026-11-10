import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Weather;

//! Colours for the day part of the day arc, following the hourly forecast:
//! yellow for sun, grey for clouds, blue-grey for rain, a cool grey for snow
//! and a soft evening red before sunset when it is clear or partly cloudy.
//! Colours are interpolated smoothly between forecast hours.
module WeatherArc {

    const SUN = 0xb89a3e;
    const PARTLY = 0x8f8a72;
    const CLOUDY = 0x5c5c5c;
    const RAIN = 0x4d6478;
    const SNOW = 0x7d8a96;
    const EVENING = 0xa85a44;

    //! Seconds before sunset in which clear or partly cloudy skies turn red.
    const EVENING_WINDOW = 3600;

    //! Keyframes [secondsOfDay, colour], sorted by time, or null without data.
    var _keys as Array<[Number, Number]>? = null;
    var _builtAt as Number = -1;

    //! Rebuild the keyframes at most every 10 minutes.
    function update(now as Number, sunset as Number) as Void {
        if (_builtAt >= 0 && now >= _builtAt && now - _builtAt < 600) {
            return;
        }
        _builtAt = now;
        _keys = build(now, sunset);
    }

    function hasData() as Boolean {
        return _keys != null;
    }

    //! Colour at a time of day (seconds since local midnight).
    function colorAt(t as Number) as Number {
        var keys = _keys;
        if (keys == null || keys.size() == 0) {
            return CLOUDY;
        }
        if (t <= keys[0][0]) {
            return keys[0][1];
        }
        for (var i = 1; i < keys.size(); i++) {
            var k1 = keys[i];
            if (t <= k1[0]) {
                var k0 = keys[i - 1];
                var span = k1[0] - k0[0];
                var f = span > 0 ? (t - k0[0]).toFloat() / span : 1.0;
                f = f * f * (3 - 2 * f);   // smooth step
                return mix(k0[1], k1[1], f);
            }
        }
        return keys[keys.size() - 1][1];
    }

    // ------------------------------------------------------------------

    function build(now as Number, sunset as Number) as Array<[Number, Number]>? {
        if (!(Toybox has :Weather)) {
            return null;
        }
        var keys = [] as Array<[Number, Number]>;
        var midnight = Time.today().value();

        var current = Weather.getCurrentConditions();
        if (current != null && current.condition != null) {
            keys.add([now, colorFor(current.condition as Number, now, sunset)]);
        }

        var hourly = Weather.getHourlyForecast();
        var lastCondition = null;
        if (hourly != null) {
            for (var i = 0; i < hourly.size(); i++) {
                var h = hourly[i];
                var time = h.forecastTime;
                var condition = h.condition;
                if (time == null || condition == null) {
                    continue;
                }
                var t = time.value() - midnight + 1800;   // middle of the hour
                if (t <= now) {
                    continue;
                }
                if (t > sunset) {
                    if (lastCondition == null) {
                        lastCondition = condition;
                    }
                    break;
                }
                keys.add([t, colorFor(condition as Number, t, sunset)]);
                lastCondition = condition;
            }
        }
        if (keys.size() == 0) {
            return null;
        }
        // Close the arc at sunset with the condition of the last hour.
        if (lastCondition != null && keys[keys.size() - 1][0] < sunset) {
            keys.add([sunset, colorFor(lastCondition as Number, sunset, sunset)]);
        }
        return keys;
    }

    function colorFor(condition as Number, t as Number, sunset as Number) as Number {
        var c = category(condition);
        if ((c == SUN || c == PARTLY) && t >= sunset - EVENING_WINDOW) {
            return EVENING;
        }
        return c;
    }

    function category(c as Number) as Number {
        if ([Weather.CONDITION_CLEAR, Weather.CONDITION_MOSTLY_CLEAR, Weather.CONDITION_FAIR,
                Weather.CONDITION_WINDY].indexOf(c) >= 0) {
            return SUN;
        }
        if ([Weather.CONDITION_PARTLY_CLOUDY, Weather.CONDITION_PARTLY_CLEAR,
                Weather.CONDITION_THIN_CLOUDS].indexOf(c) >= 0) {
            return PARTLY;
        }
        if ([Weather.CONDITION_SNOW, Weather.CONDITION_LIGHT_SNOW, Weather.CONDITION_HEAVY_SNOW,
                Weather.CONDITION_FLURRIES, Weather.CONDITION_SLEET, Weather.CONDITION_ICE,
                Weather.CONDITION_ICE_SNOW, Weather.CONDITION_WINTRY_MIX, Weather.CONDITION_FREEZING_RAIN,
                Weather.CONDITION_RAIN_SNOW, Weather.CONDITION_LIGHT_RAIN_SNOW, Weather.CONDITION_HEAVY_RAIN_SNOW,
                Weather.CONDITION_CHANCE_OF_SNOW, Weather.CONDITION_CHANCE_OF_RAIN_SNOW,
                Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW, Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW,
                Weather.CONDITION_HAIL].indexOf(c) >= 0) {
            return SNOW;
        }
        if ([Weather.CONDITION_RAIN, Weather.CONDITION_LIGHT_RAIN, Weather.CONDITION_HEAVY_RAIN,
                Weather.CONDITION_DRIZZLE, Weather.CONDITION_SHOWERS, Weather.CONDITION_LIGHT_SHOWERS,
                Weather.CONDITION_HEAVY_SHOWERS, Weather.CONDITION_SCATTERED_SHOWERS,
                Weather.CONDITION_CHANCE_OF_SHOWERS, Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN,
                Weather.CONDITION_THUNDERSTORMS, Weather.CONDITION_SCATTERED_THUNDERSTORMS,
                Weather.CONDITION_CHANCE_OF_THUNDERSTORMS, Weather.CONDITION_SQUALL,
                Weather.CONDITION_TROPICAL_STORM, Weather.CONDITION_HURRICANE, Weather.CONDITION_TORNADO,
                Weather.CONDITION_UNKNOWN_PRECIPITATION].indexOf(c) >= 0) {
            return RAIN;
        }
        return CLOUDY;   // cloudy, fog, mist, haze, smoke, dust, unknown …
    }

    function mix(a as Number, b as Number, f as Float) as Number {
        var r = mixChannel((a >> 16) & 0xff, (b >> 16) & 0xff, f);
        var g = mixChannel((a >> 8) & 0xff, (b >> 8) & 0xff, f);
        var bl = mixChannel(a & 0xff, b & 0xff, f);
        return (r << 16) | (g << 8) | bl;
    }

    function mixChannel(a as Number, b as Number, f as Float) as Number {
        return Math.round(a + (b - a) * f).toNumber();
    }
}
