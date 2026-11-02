# SudoMovies 📺

A Roku channel (SudoMovies) for sideloading onto a Roku developer device.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Powered%20by-Python-3776AB?style=flat-square)](https://www.python.org)
[![Roku](https://img.shields.io/badge/Target-Roku%20Developer%20Mode-ED1C24?style=flat-square)](https://developer.roku.com)
[![Build](https://img.shields.io/badge/Build%20-tool%20chain-0D1117?style=flat-square)](https://github.com/briggsosdev/SudoMovies)

---

## ✨ Features (tagged)

| Tag | What it does |
|-----|--------------|
| **🔑 [Metadata]** | TMDB read‑only API key for browsing, search, and genre lists. |
| **📡 [Resolvers]** | VixSrc + Febbox fallback (CineSrc PoW‑gated, StreamWish/DailyMotion/Archive removed). |
| **📺 [Live TV]** | Premium channels removed from rail; guide recomputed from programme list at wall‑clock; `1790000000` anchor, 2‑h slots. |
| **▶️ [Playback]** | `m.lastResolver` remembered per profile; auto‑play next episode reuses last resolver (`"vix"`/`"feb"`). |
| **👤 [Profiles]** | Per‑profile avatar selection; startup picker adds profile “A”. |
| **🛠️ [Injector/Deployer]** | GUI tool (`roku_inject_deploy.py` / `RokuDeploy.exe`) replaces Febbox/TMDB keys, builds zip, deploys via digest auth. |

---

## 📦 Deploy (GUI)

1. Run the tool:

   ```powershell
   python tools/roku_inject_deploy.py
   # or double‑click RokuDeploy.exe
   ```

2. **Febbox token** – paste your token (get at [febbox.com](https://febbox.com) with a fresh Google account).

3. **TMDB read‑only key** – optional; get it from [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api) and paste it into the new **TMDB Key** field. Click **Replace TMDB Key in Config.brs**.

4. Click **Auto‑Find Roku** or type the device IP, set credentials (`rokudev` / `1234`).

5. Click **Build + Deploy**.

---

## 🛠️ Deploy (CLI)

```powershell
# Set the device host (once)
$env:ROKU_HOST = "10.0.0.74"

# Then each session:
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -RokuHost 10.0.0.74
```

- Deletes existing dev channel, installs `out/roku.zip`, launches `/launch/dev`, verifies the dev channel is active.

---

## 📦 Build

Requires **Node.js 18+** and the bundled `node_modules`.

```powershell
node tools\compile.js     # must report ERRORS: none
node tools\package.js     # produces out/roku.zip
```

Or from the GUI: click **Build Package**.

---

## 📄 Notes

- Device must be in Developer Mode (Home 3×, Up 2×, Right, Left, Right, Left, Right).
- Reinstalling replaces the existing dev channel (Delete then Install).
- Personal data from the original dev build has been removed; this copy is safe to share.
- The executable `RokuDeploy.exe` is a standalone PyInstaller build (no Python needed).

---

## 📂 Repository layout

```
SudoMovies/
├─ README.md            # this file
├─ LICENSE              # MIT license
├─ CHANGELOG.md         # version history
├─ manifest             # Roku manifest
├─ components/          # BrightScript source
├─ source/              # app source code
├─ images/              # channel icons / splash
├─ tools/               # build + deploy scripts
├─ tests/               # parser / embed tests
├─ package.json / package-lock.json
└─ RokuDeploy.exe       # standalone Windows exe (PyInstaller)
```

---

## 🛠️ Development / Tooling

- **`tools/compile.js`** – BrightScript compilation + diagnostics (brighterscript toolchain).
- **`tools/package.js`** – Zips the channel (always `out/roku.zip`).
- **`tools/deploy.ps1`** – PowerShell deployment (host via `-RokuHost` or `ROKU_HOST` env).
- **`tools/deploy.js`** – Node.js alternative (host from argv or `ROKU_HOST`).
- **`tools/roku_inject_deploy.py`** – Python GUI / CLI tool (Febbox + TMDB key injection, build, deploy).
- **`RokuDeploy.exe`** – Standalone Windows executable of the above tool.

---

## 📜 Changelog

### v1.1.0 (current)

- Added **TMDB read‑only key** injection (GUI field + CLI one‑liner).
- Fixed invalid `(?<json>…)` regex → `(?P<json>…)` in Python tool.
- Added retry logic for Roku’s flaky digest handshake.
- Updated `deploy.ps1` to use real Roku XML shape for active‑app verification.
- PyInstaller exe (`RokuDeploy.exe`) rebuilt with all new code included.

### v1.0.0 (initial scrubbed release)

- Clean release copy from dev build.
- Scrubbed Febbox tokens & TMDB JWT.
- Compile / package / deploy tool fixes.
- GitHub repo creation.

---

## 🔗 Links

- **GitHub:** [https://github.com/briggsosdev/SudoMovies](https://github.com/briggsosdev/SudoMovies)
- **TMDB key:** <https://www.themoviedb.org/settings/api>
- **Febbox token:** <https://febbox.com>