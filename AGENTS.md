# Notes for contributors and coding agents

## Every change to the watch face

1. **Version:** bump according to [Semantic Versioning](https://semver.org) (while below 1.0.0: new feature → minor, fix or visual tweak → patch).
2. **Changelog:** add an entry to [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog: Added / Changed / Fixed, newest on top, compare link at the bottom).
3. **README:** update [README.md](README.md) if features, settings, sizes, build steps or the preview change.
4. **Preview:** if the look changes, update `tools/render_previews.py` to match the code and regenerate `docs/images/` (`python3 tools/render_previews.py`).
5. **Build check:** `monkeyc` for `venu3` and `venu3s` with `-l 3` (strict type check) and the store export (`-e -r`) must succeed.
6. **Release commit:** one commit `beta release X.Y.Z` plus an annotated tag `vX.Y.Z`. Do not push without being asked.

## Rules

- Never commit developer keys, account data, local paths or other personal data.
- Colours are only set with `setColor` (no `setFill`: opaque white `0xFFFFFFFF` is `-1` = transparent in Connect IQ).
- Shapes with fractional widths are drawn as single polygons; `fillCircle` and pen widths round to whole pixels.
