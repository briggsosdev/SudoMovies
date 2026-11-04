# SudoMovies 📺

A free, open-source Roku channel for sideloading onto a Roku developer device.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Powered%20by-Python-3776AB?style=flat-square)](https://www.python.org)
[![Roku](https://img.shields.io/badge/Target-Roku%20Developer%20Mode-ED1C24?style=flat-square)](https://developer.roku.com)

---

## 📖 About

**SudoMovies** lets you browse and play movies and TV shows on your Roku using free, open-source resolvers.

- **Febbox** – free video streams. Free tier = **10 GB per month**. Pick videos whose total size stays under 10 GB.
- **TMDB** – free movie/TV metadata (titles, posters, search). Optional but recommended.
- **No paid services required.** Everything is free and open-source (MIT license).

---

## ⚡ Quick Start (recommended)

The easiest way is to use the included **injector tool**. It takes the keys you paste in, writes them into the channel, builds it, and deploys it to your Roku — all in one window.

1. **Get a Febbox token** (manual – see below).
2. **Get a TMDB key** (optional) – sign up free at [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api) → create a **Read-Only** API key.
3. **Put your Roku in Developer Mode** – on the Roku remote: Home ×3, Up ×2, Right, Left, Right, Left, Right.
4. **Run the injector tool:**
   - Windows: double-click `RokuDeploy.exe`
   - Or run: `python tools/roku_inject_deploy.py`
5. In the tool:
   - Paste your **Febbox token** → click **Replace Febbox Key**.
   - Paste your **TMDB key** (optional) → click **Replace TMDB Key**.
   - Click **Auto-Find Roku** (or type your Roku's IP).
   - Click **Build + Deploy**.
6. Done! The channel appears on your Roku as a dev channel.

> 💡 **Tip:** The injector tool does **not** grab anything automatically. You copy the Febbox token from your browser's DevTools (steps below) and paste it in. The tool then writes it into the channel for you.

---

## 🔑 Keys Explained (plain English)

### Febbox token – what is it?

Febbox is a free streaming service. To use it in SudoMovies you need a **token** (a long string that proves you have an account). The token is the value of a browser cookie named **`ui`**.

- **Free tier = 10 GB per month.** That's enough for a few movies. Pick videos under 10 GB total.
- **Where do I get it?** Sign up at [febbox.com](https://febbox.com) with a fresh Google account. After logging in, the `ui` cookie is stored in your browser.
- **How do I copy it?** Open DevTools (`F12`) → Application/Storage → Cookies → `febbox.com` → find the cookie named `ui` → copy its Value (starts with `eyJ...`).
- **How do I put it in SudoMovies?** Paste it into the **Febbox Token** box in the injector tool, then click **Replace Febbox Key**. The tool writes it into the channel for you.
- **Do I need to mess with cookies after that?** No. Once it's injected, SudoMovies uses it automatically. If streams stop working later, just repeat the steps to get a fresh token.

### TMDB key – what is it?

TMDB (The Movie Database) provides movie titles, posters, and search. A **read-only API key** lets SudoMovies look up movie info.

- **Free** to get at [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api).
- **Read-only** means it can only look up info – it can't change anything.
- **Optional.** Without it, browsing still works but with less metadata.
- **How to add it:** Paste it into the **TMDB Key** field in the injector tool → click **Replace TMDB Key in Config.brs**.

### VixSrc – does it need a key?

**No.** VixSrc is a free resolver that works with no key, no cookie, and no account. It just fetches video links directly. You don't need to set anything up for it.

---

## 🛠️ Deploy (GUI) – recommended

1. Run the tool:
   ```powershell
   python tools/roku_inject_deploy.py
   # or double-click RokuDeploy.exe
   ```
2. **Febbox token** – paste the `ui` cookie value you copied from your browser. Click **Replace Febbox Key**.
3. **TMDB key** (optional) – paste it → click **Replace TMDB Key**.
4. Click **Auto-Find Roku** or type your Roku's IP. Set credentials (`rokudev` / `1234`).
5. Click **Build + Deploy**.

---

## 🛠️ Deploy (CLI) – advanced

```powershell
# Set the device host (once)
$env:ROKU_HOST = "<Roku-IP>"

# Then each session:
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -RokuHost <Roku-IP>
```

- Deletes existing dev channel, installs `out/roku.zip`, launches `/launch/dev`, verifies the dev channel is active.

---

## 📦 Build (optional)

Requires **Node.js 18+** and the bundled `node_modules`.

```powershell
node tools\compile.js     # must report ERRORS: none
node tools\package.js     # produces out/roku.zip
```

Or from the GUI: click **Build Package**.

---

## 📄 Notes

- Device must be in Developer Mode (Home ×3, Up ×2, Right, Left, Right, Left, Right).
- Reinstalling replaces the existing dev channel (Delete then Install).
- Personal data from the original dev build has been removed; this copy is safe to share.
- The executable `RokuDeploy.exe` is a standalone PyInstaller build (no Python needed).
- **Febbox free tier:** 10 GB monthly allowance – choose videos accordingly.
- **Febbox token:** it's the value of the `ui` cookie on febbox.com (copy it from DevTools). Do not log out after copying.

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

- **`tools/compile.js`** – BrightScript compilation + diagnostics.
- **`tools/package.js`** – Zips the channel (always `out/roku.zip`).
- **`tools/deploy.ps1`** – PowerShell deployment (host via `-RokuHost` or `ROKU_HOST` env).
- **`tools/deploy.js`** – Node.js alternative (host from argv or `ROKU_HOST`).
- **`tools/roku_inject_deploy.py`** – Python GUI / CLI tool (Febbox + TMDB key injection, build, deploy).
- **`RokuDeploy.exe`** – Standalone Windows executable of the above tool.

---

## 📜 Changelog

### v1.1.0 (current)
- Added **TMDB read-only key** injection (GUI field + CLI one-liner).
- Fixed invalid regex in Python tool.
- Added retry logic for Roku's flaky digest handshake.
- Updated `deploy.ps1` to use real Roku XML shape for active-app verification.
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

---

*Happy streaming, and remember: keep each video under 10 GB to stay within the free Febbox allowance!*