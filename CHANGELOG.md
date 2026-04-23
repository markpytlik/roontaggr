# Changelog

All notable changes to RoonTag. Newest first.

## 1.3.0 — 2026-04-22
- Added: in-app auto-update. On launch, RoonTag quietly checks GitHub
  Releases for a newer version and offers a one-click install. No more
  Terminal needed on the non-dev Macs.
- Added: `publish.sh` — on the dev Mac, a single command builds the app,
  zips it, and publishes a new GitHub Release with the zip attached.
- Changed: distribution model. The "dev" Mac builds + publishes; the
  other Macs just download the pre-built `.app` from GitHub Releases and
  get updates in-app.

## 1.2.0 — 2026-04-22
- Fixed: spaces no longer disappear when editing the Title field. The
  KeyRelease handler was stripping and re-writing the StringVar on every
  keystroke, which ate trailing spaces.
- Added: in-app About dialog (toolbar button) showing current version
  plus recent changelog entries.
- Added: versioning pipeline — a single `VERSION` file is the source of
  truth. `build_app.sh` reads it and stamps it into the bundle's
  `CFBundleVersion` / `CFBundleShortVersionString`.

## 1.1 — pre-2026-04-22
- Baseline feature set: drag-and-drop tagging, artwork paste/fetch,
  DJ-mix tracklist support, Roon-friendly TPE1/TPE2/TDRC handling.
