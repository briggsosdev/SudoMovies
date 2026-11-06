# SudoMovies — Samsung Tizen scaffold

This folder is a **starter skeleton** for running SudoMovies on a Samsung (Tizen) TV. It is NOT a full port — the Roku BrightScript channel cannot run on Tizen. This is an HTML5/JS web app shell that you sideload via Tizen Studio.

## What's included
- `config.xml` — Tizen widget manifest
- `index.html` / `css/style.css` / `js/main.js` — basic UI with TMDB browsing + a video player element
- Stream resolution (Febbox/VixSrc) is **not** wired up — `openPlayer()` is a stub. Wire a backend (e.g. a pmor-style server) or implement resolvers in JS.

## Requirements
- Tizen Studio (with TV extensions) installed on a PC
- Samsung TV in Developer Mode (Settings → Smart Hub → Apps → 12345 → Developer Mode on, enter your PC IP)
- TV and PC on the same network

## Build & install
1. Open Tizen Studio → File → Import → Tizen Project → select this `samsung/` folder.
2. Right-click project → Build Signed Package (create a certificate first via Certificate Manager).
3. Connect TV: Device Manager → scan → connect to your TV IP.
4. Run As → Tizen Web Application (or use sdb: `sdb install <package>.wgt`).

## Notes
- Replace `YOUR_TMDB_KEY_HERE` in `js/main.js` with a real TMDB read key.
- Remote keys: Tizen maps remote buttons to standard keydown events; adjust as needed.
- This is a scaffold only — full feature parity with the Roku channel requires a complete rewrite.
