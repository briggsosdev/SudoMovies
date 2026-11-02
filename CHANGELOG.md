# SudoMovies Changelog

All notable changes to this project will be documented in this file.

## v1.1.0 – 2026‑11‑02

- **Added TMDB read‑only key injection** – GUI field and one‑liner (`tools/roku_inject_deploy.py` + `RokuDeploy.exe`).
- **Fixed invalid `(?<json>…)` regex** → `(?P<json>…)` in `roku_inject_deploy.py` (Python 3 compat).
- **Added retry logic** for Roku’s flaky digest auth handshake (`_request()` helper).
- **Updated `deploy.ps1`** to parse the real Roku XML shape (`<app id="dev" …>Name</app>`) for active‑app verification; exits nonzero on failed install/launch.
- **PyInstaller exe (`RokuDeploy.exe`)** rebuilt with all new code included; size ~16 MB.
- **TMDB key button** added to the injector GUI (text box + “Replace TMDB Key in Config.brs”).
- **`ConfigLoad()`** in the release copy now preserves any user‑saved registry token instead of overwriting with blank default.

## v1.0.0 – 2026‑11‑02

- Clean release copy from dev build.
- Scrubbed Febbox tokens and TMDB JWT from `components/Config.brs` and `components/Constants.brs`.
- Compile / package / deploy tool fixes (`package.js`, `deploy.ps1`, `deploy.js`, `roku_inject_deploy.py`).
- GitHub repository created at <https://github.com/briggsosdev/SudoMovies>.
- README with build / deploy instructions and feature overview.

---

## Future ideas

- Proxy‑free resolver support (VixSrc + Febbox only).
- Per‑profile avatar system.
- Live‑TV guide recomputation from programme lists at wall‑clock.
- Auto‑play next episode reusing last resolver.