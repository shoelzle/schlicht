# Notes for contributors and coding agents

## Every change to the watch face

1. **Version:** bump according to [Semantic Versioning](https://semver.org): new setting or feature → minor, fix or visual tweak → patch, a redesign that changes the face's character → major.
2. **Changelog:** add an entry to [CHANGELOG.md](CHANGELOG.md) (Keep a Changelog: Added / Changed / Fixed, newest on top, compare link at the bottom).
3. **README:** update [README.md](README.md) if features, settings, sizes, build steps or the preview change.
4. **Preview:** if the look changes, update `tools/render_previews.py` to match the code and regenerate `docs/images/` (`python3 tools/render_previews.py`).
5. **Build check:** `monkeyc` for `venu3` and `venu3s` with `-l 3` (strict type check) and the store export (`-e -r`) must succeed.
6. **Release commit:** one commit `release X.Y.Z` plus an annotated tag `vX.Y.Z` (up to 0.3.14: `beta release X.Y.Z`). Do not push without being asked. Upload the exported `schlicht.iq` to the store with the same version number.

## App IDs

- `manifest.xml` holds the ID of the **public** store app: `9a6636c3-3c49-4334-aa2f-f6aff3408073`. Never change it, or the store treats the face as a new app and users lose their settings.
- Beta apps in the Connect IQ Store are never released, and a public app cannot use a beta app's ID. For a private test build with settings, temporarily replace the ID with the beta ID `01d5e0ac-1675-4dd8-ae9d-ca095a244988`, export, upload as a new version of the beta app, and do not commit that change.

## Rules

- Never commit developer keys, account data, local paths or other personal data.
- Colours are only set with `setColor` (no `setFill`: opaque white `0xFFFFFFFF` is `-1` = transparent in Connect IQ).
- Shapes with fractional widths are drawn as single polygons; `fillCircle` and pen widths round to whole pixels.
