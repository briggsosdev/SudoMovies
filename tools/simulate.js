"use strict";
/**
 * Local SceneGraph harness for the Roku channel.
 *
 * Boots the real channel in brs-node (no TV, no network Roku, no deployment),
 * captures PNG screenshots, and injects remote key presses through the same
 * SharedArrayBuffer control slots the official brs-cli keyboard driver uses.
 *
 * Usage:
 *   node tools/simulate.js                        # boot + auto screenshots
 *   node tools/simulate.js --keep                 # leave the device running
 *   node tools/simulate.js --key Up --key Select  # explicit key script
 *
 * IMPORTANT (brs-node 2.6.0 SceneGraph limitation): the simulator repaints only
 * when the scene *tree* changes -- appendChild / removeChild / showScene.
 * Mutating a field (label text, rect width/color, content of an existing list)
 * does NOT produce a new frame. Verified with a minimal repro. So screenshots
 * only move for scenes that attach or detach nodes, and an unchanged screenshot
 * after a key press does not prove the UI failed to update.
 */

const fs = require("node:fs");
const path = require("node:path");
const brs = require("brs-node");

const ROOT = path.resolve(__dirname, "..");
const SHOTS = path.join(ROOT, "tools", "out", "shots");

// Package dirs, matching the manifest/build scope. `components` recurses.
const INCLUDE_DIRS = ["source", "components", "images"];
const INCLUDE_FILES = ["manifest"];

// Control-slot layout of the interpreter SharedArrayBuffer (DataType enum).
const RID = 29;
const KEY = 30;
const MOD = 31;
const SLOT_STRIDE = 6;
const SLOT_COUNT = 3;
const RemoteType = { IR: 10, WD: 20, BT: 30, SIM: 40, ECP: 50 };
const KEY_CODES = {
  back: 0, up: 2, down: 3, left: 4, right: 5,
  select: 6, ok: 6, enter: 6,
  instantreplay: 7, rev: 8, fwd: 9, info: 10, backspace: 11,
  play: 13, pause: 13, a: 17, b: 18, x: 24, y: 25,
  l1: 26, r1: 27, l2: 28, r2: 29,
};
const CLI_LENGTH = brs.DataBufferIndex + brs.DataBufferSize;

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const opt = (f) => {
  const i = args.indexOf(f);
  return i >= 0 ? args[i + 1] : undefined;
};
const keyScript = args.reduce((acc, a, i) => (a === "--key" ? [...acc, args[i + 1]] : acc), []);

function collectChannelFiles() {
  const files = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else {
        files.push(full);
      }
    }
  };
  for (const dir of INCLUDE_DIRS) {
    const full = path.join(ROOT, dir);
    if (fs.existsSync(full)) {
      walk(full);
    }
  }
  for (const file of INCLUDE_FILES) {
    const full = path.join(ROOT, file);
    if (fs.existsSync(full)) {
      files.push(full);
    }
  }
  return files;
}

function relativeToPkg(full) {
  return path.relative(ROOT, full).split(path.sep).join("/");
}

async function auditAssets(fileMap, manifest) {
  const issues = [];

  const exists = (rel) => fileMap.has(rel);
  const strip = (ref) => ref.replace(/^pkg:\/*/, "").split("?")[0];

  // Manifest keys are not a fixed set (mm_icon_focus_hd, splash_screen_fhd,
  // splash_color, ...), so audit every value rather than a hardcoded list.
  for (const [field, ref] of manifest) {
    if (typeof ref !== "string" || !ref.startsWith("pkg:")) {
      continue;
    }
    const rel = strip(ref);
    if (!exists(rel)) {
      issues.push(`manifest ${field} -> missing pkg file: ${rel}`);
    }
  }

  // Two guards against false positives:
  //  - BrightScript ' comments are stripped, so prose such as
  //    "never pkg:/ fallbacks" is not mistaken for a reference.
  //  - The ref must start with a name character. Without this, the slash in a
  //    bare "pkg:/" matches and gets reported as a missing file named "/".
  const stripComments = (value) => value.replace(/'(?:[^'\n]|'')*/g, " ");

  const collectRefs = (value, out) => {
    const re = /pkg:\/*([A-Za-z0-9_][A-Za-z0-9_\-./]*)/g;
    let m;
    const code = stripComments(value);
    while ((m = re.exec(code))) {
      out.push(m[1]);
    }
  };

  // Scan both BrightScript and SceneGraph XML: XML holds the poster, focus
  // bitmap and script uri references, and a typo there fails at runtime only.
  for (const [rel, buffer] of fileMap) {
    if (!rel.endsWith(".brs") && !rel.endsWith(".xml")) {
      continue;
    }
    const refs = [];
    // fileMap values are Blobs: Blob.toString() yields "[object Blob]", so the
    // text has to be read with .text() or the audit silently scans nothing.
    collectRefs(await buffer.text(), refs);
    for (const ref of refs) {
      if (!exists(ref)) {
        issues.push(`${rel} -> unresolved pkg: ref ${ref}`);
      }
    }
  }

  return issues;
}

function makeFileMap(files) {
  const map = new Map();
  for (const full of files) {
    map.set(relativeToPkg(full), new Blob([fs.readFileSync(full)]));
  }
  return map;
}

async function main() {
  fs.mkdirSync(SHOTS, { recursive: true });
  for (const old of fs.readdirSync(SHOTS)) {
    fs.unlinkSync(path.join(SHOTS, old));
  }

  const files = collectChannelFiles();
  console.log(`[harness] packaging ${files.length} files from channel scope`);

  const fileMap = makeFileMap(files);

  // The SceneGraph extension is loaded by name: the interpreter resolves the
  // module path from device.extensions, then instantiates BrightScriptExtension.
  const sgPath = require.resolve("brs-node/bin/brs-sg.node.js");
  const sg = require(sgPath);
  brs.registerExtension(() => sg.BrightScriptExtension);

  const device = {
    ...brs.DefaultDeviceInfo,
    developerId: "dev",
    displayMode: "720p",
    extensions: new Map([[brs.SupportedExtension.SceneGraph, sgPath]]),
  };

  const payload = await brs.createPayloadFromFiles([], device, undefined, ROOT);
  payload.extensions = [brs.SupportedExtension.SceneGraph];
  console.log(`[harness] manifest title : ${payload.manifest.get("title")}`);
  console.log(`[harness] manifest major : ${payload.manifest.get("major_version")}`);
  console.log(`[harness] source files   : ${payload.paths.length}`);

  const issues = await auditAssets(fileMap, payload.manifest);
  if (issues.length === 0) {
    console.log("[harness] asset audit     : OK (all pkg: refs resolve)");
  } else {
    console.log(`[harness] asset audit     : ${issues.length} issue(s)`);
    for (const issue of issues) {
      console.log(`           - ${issue}`);
    }
  }

  const sharedBuffer = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * CLI_LENGTH);
  const control = new Int32Array(sharedBuffer);
  control.fill(-1);

  let shotIndex = 0;
  let lastFrame = null;
  let frameCount = 0;

  const distinctColors = (frame) => {
    const seen = new Set();
    const data = frame.data;
    for (let i = 0; i < data.length; i += 4) {
      seen.add(((data[i] << 16) | (data[i + 1] << 8) | data[i + 2]) >>> 0);
      if (seen.size > 4000) {
        break;
      }
    }
    return seen.size;
  };

  // Waits until the compositor stops producing blank clear frames, so a
  // screenshot never captures a single-colour pre-layout frame.
  const waitForContent = async (timeoutMs = 15000) => {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      if (lastFrame && frameCount > 2 && distinctColors(lastFrame) > 8) {
        return true;
      }
      await sleep(200);
    }
    return false;
  };

  // Cheap frame fingerprint: brs-node only repaints on tree changes, so an
  // identical fingerprint means the compositor has not repainted at all.
  let lastShotSignature = null;

  const frameSignature = (frame) => {
    let h = 0;
    const data = frame.data;
    for (let i = 0; i < data.length; i += 397) {
      h = (h * 33 + data[i]) | 0;
    }
    return h;
  };

  const shot = async (label) => {
    if (!lastFrame) {
      console.log(`[harness] shot ${label} skipped: no frame rendered yet`);
      return;
    }
    const isFirst = lastShotSignature === null;
    const signature = frameSignature(lastFrame);
    const changed = !isFirst && signature !== lastShotSignature;
    lastShotSignature = signature;
    const name = `shot-${String(++shotIndex).padStart(2, "0")}-${label}.png`;
    const canvas = brs.createNewCanvas(lastFrame.width, lastFrame.height);
    canvas.getContext("2d").putImageData(lastFrame, 0, 0);
    fs.writeFileSync(path.join(SHOTS, name), canvas.toBuffer("image/png"));
    console.log(
      `[harness] saved ${name} (${lastFrame.width}x${lastFrame.height}, ` +
        `frame #${frameCount}, ${distinctColors(lastFrame)} colors, ` +
        `${isFirst ? "first shot" : changed ? "repainted" : "IDENTICAL to previous shot"})`
    );
  };

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // The interpreter consumes a key slot and resets it, so we must claim a free
  // slot (KEY < 0) rather than always writing slot 0, and release it afterwards.
  const claimSlot = () => {
    for (let i = 0; i < SLOT_COUNT; i++) {
      const base = i * SLOT_STRIDE;
      if (Atomics.load(control, KEY + base) < 0) {
        return base;
      }
    }
    for (let i = 1; i < SLOT_COUNT; i++) {
      const dst = (i - 1) * SLOT_STRIDE;
      const src = i * SLOT_STRIDE;
      Atomics.store(control, RID + dst, Atomics.load(control, RID + src));
      Atomics.store(control, KEY + dst, Atomics.load(control, KEY + src));
      Atomics.store(control, MOD + dst, Atomics.load(control, MOD + src));
    }
    return (SLOT_COUNT - 1) * SLOT_STRIDE;
  };

  const sendKey = async (name, mod = 0, holdMs = 120) => {
    const code = KEY_CODES[String(name).toLowerCase()];
    if (code === undefined) {
      console.log(`[harness] unknown key '${name}' - ignored`);
      return;
    }
    const base = claimSlot();
    Atomics.store(control, RID + base, RemoteType.SIM);
    Atomics.store(control, MOD + base, mod);
    Atomics.store(control, KEY + base, code + mod);
    await sleep(holdMs);
    Atomics.store(control, KEY + base, -1);
    return base;
  };

  brs.subscribeHost("simulate", (type, payloadArg) => {
    if (type === "frame") {
      lastFrame = payloadArg;
      frameCount++;
    } else if (type === "error") {
      console.error(`[app:error] ${payloadArg}`);
    } else if (type === "warning") {
      console.warn(`[app:warn] ${payloadArg}`);
    } else if (type === "stderr") {
      console.error(`[app:stderr] ${payloadArg}`);
    }
  }, sharedBuffer);

  console.log("[harness] booting channel");
  const run = brs.executeApp(payload, { sharedBuffer, stopOnCrash: true });

  await waitForContent();
  await shot("splash");

  await sleep(6000);
  await waitForContent();
  await shot("home");

  for (const key of keyScript) {
    await sendKey(key);
    await sleep(1200);
    await waitForContent(6000);
    await shot(`key-${key}`);
  }

  if (!has("--keep")) {
    brs.terminateApp(brs.AppExitReason.UserNav, 2000);
  }

  const result = await run;
  console.log(`[harness] exit reason: ${result.exitReason}`);
  console.log(`[harness] screenshots in ${path.relative(ROOT, SHOTS)}`);
}

main().catch((error) => {
  console.error("[harness] fatal:", error && error.stack ? error.stack : error);
  process.exitCode = 1;
});