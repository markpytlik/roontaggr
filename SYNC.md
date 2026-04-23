# RoonTag — distribution across your Macs

Distribution model: one "dev" Mac builds + publishes a new release to
GitHub; the other Macs download the pre-built `.app` and update
themselves from inside RoonTag. No Terminal required on the non-dev
Macs after the initial install.

---

## Dev Mac (this one) — one-time setup

The source folder already has git initialized and is pushed to
`github.com/markpytlik/roontaggr`. To publish a release you need the
GitHub CLI:

```bash
brew install gh
gh auth login    # pick GitHub.com → SSH → use existing key
```

Optional convenience:

```bash
cd ~/Documents/Claude/Projects/"Music Metadata"/roontaggr
chmod +x roontag-update publish.sh
ln -sf "$(pwd)/publish.sh"       /usr/local/bin/roontag-publish
ln -sf "$(pwd)/roontag-update"   /usr/local/bin/roontag-update
```

---

## Other Macs — one-time install

No Python, no Xcode, no Terminal gymnastics. Just:

1. Open `https://github.com/markpytlik/roontaggr/releases/latest` in a
   browser.
2. Download `RoonTag.app.zip`.
3. Unzip (Finder does this automatically on double-click).
4. Drag `RoonTag.app` into `/Applications`.
5. First launch: right-click → Open (macOS asks once because the build
   is ad-hoc signed).

Done. From here on, RoonTag checks for updates on launch and offers a
one-click install when a newer version is available.

---

## Day-to-day workflow

**On the dev Mac, after making a code change:**

1. Edit `VERSION` — bump the number (e.g. `1.3.0` → `1.3.1`).
2. Add an entry to the top of `CHANGELOG.md` with today's date.
3. Commit + publish:

   ```bash
   git commit -am "vX.Y.Z — <summary>"
   git push
   roontag-publish        # builds, zips, uploads to GitHub Releases
   ```

**On the other Macs:**

Open RoonTag. It'll notice the new release, show a dialog with the
changelog entry, and a single click installs it and relaunches.

Or: click **Check for Updates** in the toolbar to check manually.

---

## What's where

| File               | Role                                                     |
| ------------------ | -------------------------------------------------------- |
| `VERSION`          | Single source of truth for version number.               |
| `CHANGELOG.md`     | Surfaced in the in-app About dialog + release notes.     |
| `app.py`           | The tkinter GUI + update checker.                        |
| `setup.sh`         | Creates Python venv on dev Mac. Run once per dev Mac.    |
| `build_tkdnd.sh`   | Compiles tkdnd native lib. Run once per dev Mac.         |
| `build_app.sh`     | Reads VERSION, packages `.app`, installs to /Applications. |
| `publish.sh`       | Builds + zips + creates GitHub Release with the zip.     |
| `roontag-update`   | `git pull && build_app.sh` (dev Mac maintenance).        |
