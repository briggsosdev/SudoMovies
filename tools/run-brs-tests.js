#!/usr/bin/env node
/*
 * Runs the BrightScript parser regression suite.
 *
 * TWO GATES, in order:
 *
 *   1. brighterscript (the real Roku compiler) must compile the whole channel
 *      with zero errors.
 *   2. the npm `brs` interpreter executes the value assertions.
 *
 * Gate 1 exists because `brs` is NOT a faithful BrightScript parser. It
 * happily accepts constructs Roku rejects, such as passing a bare expression
 * as a function argument. A suite checked only by `brs` can therefore pass
 * while the file would not compile on a device - which is exactly what
 * happened to this repo's first version of this suite.
 *
 * Why a suite at all: the Urban / reanime parsers were "syntax clean" while
 * silently returning zero records, so the home rows rendered empty and no
 * error ever surfaced. A syntax-only check cannot catch that class of bug,
 * so the suite asserts on returned VALUES against captured live HTML.
 *
 * The npm `brs` interpreter has no roUrlTransfer and no SceneGraph, so this
 * harness can only exercise the pure-string layer. It links the exact
 * component sources used by the app rather than copies, so a regression in
 * the real file fails the test.
 *
 * Usage: npm test
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const zlib = require("zlib");
const { execFileSync, execSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const COMPONENTS = path.join(ROOT, "components");
const FIXTURES = path.join(ROOT, "tests", "fixtures");

// Sources the suite links in, in dependency order.
const SOURCES = [
  path.join(COMPONENTS, "UrbanCatalog.brs"),
  path.join(COMPONENTS, "UrbanAnime.brs"),
  path.join(COMPONENTS, "UrbanVideoEmbed.brs"),
  path.join(COMPONENTS, "tasks", "YoutubeTask.brs"),
  path.join(ROOT, "tests", "verify_parsers.brs"),
];

// components/ is packaged into the shipped channel, so the HTML fixtures are
// checked in gzipped (~10:1) and expanded into a temp dir at test time.
const FIXTURE_FILES = ["reanime", "reanime_entity", "ok_embed", "vidmoly_embed"];

function expandFixtures() {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), "roku-brs-fixtures-"));
  for (const name of FIXTURE_FILES) {
    const gz = path.join(FIXTURES, name + ".html.gz");
    if (!fs.existsSync(gz)) {
      fail("missing fixture " + name + ".html.gz (regenerate with tools/fetch_fixtures.ps1)");
    }
    const html = zlib.gunzipSync(fs.readFileSync(gz));
    fs.writeFileSync(path.join(out, name + ".html"), html);
  }
  return out;
}

function resolveBrs() {
  const candidates = [];
  // 1. Repo-local dev dependency (the normal case for CI).
  candidates.push(path.join(ROOT, "node_modules", "brs", "bin", "cli.js"));
  // 2. A globally installed brs.
  try {
    // execSync, not execFileSync: on Windows npm is a .cmd shim, so it needs
    // a shell. execSync is shell-by-design and avoids passing unescaped args.
    const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
    if (globalRoot) candidates.push(path.join(globalRoot, "brs", "bin", "cli.js"));
  } catch (e) {
    /* npm not on PATH; the local-install candidate above may still satisfy us */
  }
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  return null;
}

function fail(message) {
  console.error("TEST RUNNER ERROR: " + message);
  process.exit(2);
}

const brs = resolveBrs();
if (!brs) fail("could not locate the brs interpreter. Run: npm install --save-dev brs");

/*
 * The npm `brs` interpreter does not implement `try`/`catch`, which BrightScript
 * has supported for years and which the Roku build accepts. Gate 1
 * (brighterscript) is what actually validates those blocks; this shim only
 * exists so the interpreter can parse the file far enough to run the pure
 * functions under test. It is applied to the execution copy ONLY - the real
 * sources on disk are never modified.
 */
function stripTryCatch(src, file) {
  const lines = src.split(/\r?\n/);
  const out = [];
  let depth = 0;
  let removed = 0;
  for (const line of lines) {
    const t = line.trim();
    if (depth === 0 && /^try$/i.test(t)) {
      depth = 1;
      removed++;
      continue;
    }
    if (depth > 0) {
      if (/^end\s+try$/i.test(t)) {
        depth--;
        continue;
      }
      // Everything between try and end try (including `catch e`) is dropped.
      removed++;
      continue;
    }
    out.push(line);
  }
  if (depth !== 0) {
    console.error("stripTryCatch: unbalanced try in " + path.basename(file));
    process.exit(2);
  }
  if (removed) {
    console.log("  note: stripped " + removed + " try/catch line(s) from " + path.basename(file) + " (brs lacks support; gate 1 still checks them)");
  }
  return out.join("\n");
}

function buildBundle() {
  return SOURCES.map((f) => stripTryCatch(fs.readFileSync(f, "utf8"), f)).join("\n");
}

const fixtureDir = expandFixtures();

// ---- GATE 1: real Roku compiler -------------------------------------------
// Gate 2 (`brs`) is lenient; it will happily run code a Roku rejects. Never
// trust it as the sole syntax authority.
console.log("=== GATE 1: brighterscript compile (real Roku compiler) ===");
let compileOk = true;
try {
  const bsc = path.join(ROOT, "node_modules", ".bin", process.platform === "win32" ? "bsc.cmd" : "bsc");
  if (!fs.existsSync(bsc)) fail("brighterscript not installed. Run: npm install --save-dev brighterscript");
  // execSync (shell by design) rather than execFileSync+shell:true: the paths
  // here are all repo-relative and fixed, and shell:true emits a Node
  // deprecation warning about unescaped args on every run.
  const out = execSync('"' + bsc + '" --rootDir "' + ROOT + '" --create-package false', {
    encoding: "utf8",
    cwd: ROOT,
  });
  const clean = out.replace(/\x1b\[[0-9;]*m/g, "");
  const errs = clean.match(/^[^\s:]+\.(brs|xml):\d+:\d+ - error BS\d+:.*$/gm) || [];
  if (errs.length) {
    compileOk = false;
    console.log(clean);
    console.log("COMPILE ERRORS: " + errs.length);
  } else {
    console.log("compile: clean");
  }
} catch (e) {
  // bsc exits nonzero when there are errors; its output carries the detail.
  const clean = ((e.stdout || "") + (e.stderr || "")).replace(/\x1b\[[0-9;]*m/g, "");
  const errs = clean.match(/^[^\s:]+\.(brs|xml):\d+:\d+ - error BS\d+:.*$/gm) || [];
  if (errs.length) {
    compileOk = false;
    console.log(clean);
    console.log("COMPILE ERRORS: " + errs.length);
  } else {
    compileOk = false;
    console.log(clean);
    console.log("COMPILE FAILED (no diagnostics parsed)");
  }
}

if (!compileOk) {
  console.error("");
  console.error("gate 1 failed: the channel does not compile. Fix this before trusting any test result.");
  process.exit(1);
}
console.log("");

// ---- GATE 2: value assertions --------------------------------------------
console.log("=== GATE 2: value assertions (brs interpreter) ===");

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "roku-brs-tests-"));
const script = path.join(tmp, "suite.brs");

const bundle = buildBundle();
fs.writeFileSync(script, bundle, "utf8");

let output = "";
let exitCode = 0;
try {
  output = execFileSync(process.execPath, [brs, script, "-r", fixtureDir], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  });
} catch (e) {
  output = (e.stdout || "") + (e.stderr || "");
  exitCode = e.status === undefined ? 1 : e.status;
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.rmSync(fixtureDir, { recursive: true, force: true });
}

process.stdout.write(output);

const passes = (output.match(/\bpass\b/g) || []).length;
const failures = (output.match(/\bFAIL\b/g) || []).length;

console.log("");
console.log("assertions passed: " + passes + "   failed: " + failures);

if (exitCode !== 0) {
  console.error("interpreter exited with code " + exitCode);
  process.exit(1);
}
if (failures > 0) {
  console.error("suite reported failures");
  process.exit(1);
}
if (/RESULT: ALL TESTS PASSED/.test(output) === false) {
  console.error("suite did not report success");
  process.exit(1);
}

console.log("OK");