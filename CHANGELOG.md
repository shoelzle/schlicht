# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
While the version is below 1.0.0, minor versions may also contain changes to the look of the watch face.

## [0.3.6] – 2026-11-10

### Changed
- Sunrise marker about 20 % larger (rays reach 18.5 instead of 15.45 px, disc radius 8.4 px), so the sun looks as large as the crescent moon at sunset. Proportions and gap stay the same.

## [0.3.5] – 2026-11-10

### Changed
- Sunrise marker: the gap between the sun's disc and its rays is about 25 % larger (2.25 instead of 1.8 px); the rays keep their length and move outwards.

## [0.3.4] – 2026-11-10

### Changed
- New sunrise marker: a slightly larger, bright yellow sun with eight triangular rays and a small gap to the disc, instead of the muted sun with thin bars.
- The watch face project now lives in the repository root (`manifest.xml`, `monkey.jungle`, `source/`, `resources/`) instead of `watchfaces/schlicht/`. Open the repository folder itself in VS Code; build commands no longer need `cd`.

## [0.3.3] – 2026-11-10

### Changed
- The notification dots are now part of the watch face (`source/NotificationDots.mc`) instead of a separate barrel. The look and press-and-hold behaviour are unchanged; building no longer needs the barrel path or a barrel dependency in the manifest.

### Removed
- The barrel project `barrels/notification-dots`.

## [0.3.2] – 2026-11-09

### Changed
- New launcher icon: a simplified *Schlicht* face with hands, twelve dots and a coloured day arc, instead of the old placeholder.
- Project renamed to *Schlicht* (README title, licence holder `The schlicht authors`); the repository is `shoelzle/schlicht`.

### Fixed
- README: press and hold on the notification dots is confirmed to open the notification list on a Venu 3.

## [0.3.1] – 2026-11-09

### Changed
- Rounder hand tips: the rounded end at the tip is now a finer half circle (12 instead of 6 edges), so it no longer looks slightly pointed on the watch.

## [0.3.0] – 2026-11-09

### Added
- Spiral day arc on long days: if sunrise and sunset are more than 11 hours apart, the arc moves inwards by 8 px per 12 hours, so its end never overlaps its start. Sun, moon and their times follow the spiral.

### Changed
- Hour, minute and second hand 15 % thicker.
- Heart rate number, heart and date 15 % larger; the heart outline is drawn 20 % thicker.
- The day arc is no longer cut off after 12 hours; on long days it now ends at sunset as a spiral.

### Fixed
- Small bumps at both ends of the hands. The rounded ends are now part of one polygon instead of separate circles, which Connect IQ rounds to whole pixels.

## [0.2.1] – 2026-11-07

### Changed
- Sun and moon markers twice as large; sunrise and sunset times about 33 % larger and a little further away from the markers.
- Day arc about 25 % thicker (2.5 px).
- The day arc is hidden at night; sun, moon and their times stay visible.

### Fixed
- Hands appeared grey and translucent, the second hand and the centre were invisible: opaque white as ARGB (`0xFFFFFFFF`) equals `-1`, which Connect IQ treats as transparent. Colours are now only set with `setColor`; the soft edge uses solid greys.
- Date showed "Sat 07": now weekday in the watch's language and day without a leading zero.
- Sunrise and sunset times were off in the simulator: they now come from `Weather.getSunrise/getSunset` for the weather location, with the native complications as fallback.
- Text was about 30 % smaller on the watch than designed: fonts are now calibrated by their actual digit height.
- Heart and date were not vertically aligned: both are now centred by digit height.
- Sun rays touched the sun: rays are now drawn as exact polygons with a clear gap.

## [0.2.0] – 2026-11-07

First beta release of the *Schlicht* watch face for Venu 3 and Venu 3S.

### Added
- Analog watch face, white on black: slim white hands with soft edges, 60 grey minute dots at the edge, every fifth one larger and lighter, no numerals.
- Day arc from the hour hand to sunset, coloured by the hourly weather forecast, fading in before the hour hand and out towards sunset; sunrise marked with a sun, sunset with a moon, each with its time.
- Date and heart rate (number only while a live reading is available).
- Unread phone notifications as fading dots; press and hold to open the notification list. Built as the reusable barrel `NotificationDots` 0.1.0.
- Always-on mode with thin hands and twelve dots, shifting every minute to follow AMOLED burn-in rules.
- Setting to turn the second hand on or off.

[0.3.6]: https://github.com/shoelzle/schlicht/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/shoelzle/schlicht/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/shoelzle/schlicht/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/shoelzle/schlicht/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/shoelzle/schlicht/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/shoelzle/schlicht/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/shoelzle/schlicht/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/shoelzle/schlicht/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/shoelzle/schlicht/releases/tag/v0.2.0
