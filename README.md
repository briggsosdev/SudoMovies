# SudoMovies (release build)

A Roku channel (SudoMovies) packaged for sideloading onto a Roku developer device.

## Before you run

This build ships with **no API keys**. You must supply your own:

1. **TMDB read-only API key** (free) - https://www.themoviedb.org/settings/api
2. **Febbox token** (free) - sign up at https://www.febbox.com with a fresh Google account, then copy your token from browser storage/network requests.

On the Roku device, open **Settings** in the app and use the three steps (Febbox token, optional provider URL, TMDB key) to paste them. Values are saved to the device registry.

## Build

Requires Node.js 18+ and the bundled `node_modules`.

```
node tools/compile.js
node tools/package.js
```

`tools/compile.js` must report `ERRORS: none`. `tools/package.js` produces `out/roku.zip`.

## Deploy (GUI)

```
python tools/roku_inject_deploy.py
```

- Paste your Febbox token into the token box and click **Replace Febbox Key in Config.brs** (optional; you can also enter it on-device).
- Click **Auto-Find Roku** or type the device IP, set credentials (default `rokudev` / `1234`).
- Click **Build + Deploy**.

## Deploy (CLI)

```
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -RokuHost <device-ip>
```

Or set `ROKU_HOST=<device-ip>` and run `powershell -File tools\deploy.ps1`.

## Notes

- Device must be in Developer Mode (press Home 3x, Up 2x, Right, Left, Right, Left, Right).
- Reinstalling replaces the existing dev channel (Delete then Install).
- Personal data from the original dev build has been removed; this copy is safe to share.
