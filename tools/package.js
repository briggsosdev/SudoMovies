// Build a real .zip channel package with brighterscript, the same packaging
// the Roku build server uses, then print what went in. Run before deploying so
// the artifact is inspectable.
const fs = require("node:fs");
const path = require("node:path");
const bs = require("brighterscript");

const ROOT = path.resolve(__dirname, "..");
// brighterscript writes the package to <rootDir>/out regardless of stagingDir,
// so the artifact search must look at out/, not tools/out/.
const OUT = path.join(ROOT, "out");
// Always ship a stable artifact name. brighterscript defaults the zip name to
// the root folder name, which breaks deploy.ps1 and the Python tool when the
// project is copied into a folder such as "SUDO RELEASE".
const PKG = path.join(OUT, "roku.zip");

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  // Remove a previous artifact first: a failed build must not leave an old zip
  // behind for the deploy step to upload silently.
  if (fs.existsSync(PKG)) fs.rmSync(PKG, { force: true });

  const builder = new bs.ProgramBuilder();
  await builder.run({
    cwd: ROOT,
    rootDir: ROOT,
    manifestPath: "manifest",
    files: [
      "manifest",
      "components/**/*.brs",
      "components/**/*.xml",
      "source/**/*.brs",
      "images/**/*",
    ],
    staging: false,
    // NOTE: stagingDir must NOT point inside the scanned root - the staging
    // tree would be picked up as channel source. Build straight into out/.
    outFile: "out/roku.zip",
    deploy: false,
    watch: false,
    createPackage: true,
    logLevel: "error",
    showDiagnosticsInConsole: false,
  });

  const diags = builder.getDiagnostics();
  const errors = diags.filter((d) => d.severity === 0);
  if (errors.length) {
    console.log("BUILD FAILED: " + errors.length + " error(s)");
    for (const e of errors.slice(0, 20)) {
      console.log("  " + (e.filePath || e.file?.pkgPath || "?") + " " + (e.message || ""));
    }
    process.exit(1);
  }

  const program = builder.program;
  console.log("files in package : " + Object.keys(program.pkgMap || {}).length);

  // Verify the artifact the deploy step will actually upload: it must exist,
  // and its entries must use forward slashes. Backslash-separated entries are
  // the classic Windows zip failure - the device unpacks nothing and then
  // reports "Script directory /source does not exist in plugin".
  if (!fs.existsSync(PKG)) {
    console.log("no zip produced at " + path.relative(ROOT, PKG));
    process.exit(1);
  }
  const size = fs.statSync(PKG).size;
  console.log("package          : " + path.basename(PKG) + "  (" + (size / 1024).toFixed(1) + " KB)");
  console.log("path             : " + path.relative(ROOT, PKG));

  const entries = [];
  try {
    const buf = fs.readFileSync(PKG);
    // Walk the local file headers just enough to collect names.
    for (let i = 0; i + 30 < buf.length; ) {
      if (buf.readUInt32LE(i) !== 0x04034b50) { i++; continue; }
      const nameLen = buf.readUInt16LE(i + 26);
      const extraLen = buf.readUInt16LE(i + 28);
      const name = buf.toString("utf8", i + 30, i + 30 + nameLen);
      if (name) entries.push(name);
      i += 30 + nameLen + extraLen;
    }
  } catch (e) {
    console.log("zip listing failed: " + e.message);
    process.exit(1);
  }

  const bad = entries.filter((n) => n.includes("\\"));
  const dirs = entries.filter((n) => n.endsWith("/"));
  console.log("entries          : " + entries.length + " (" + dirs.length + " dirs)");
  if (bad.length) {
    console.log("BACKSLASH ENTRIES (device cannot unpack these):");
    for (const b of bad.slice(0, 10)) console.log("  " + b);
    process.exit(1);
  }
  for (const required of ["manifest", "source/main.brs"]) {
    const hit = entries.some((n) => n === required || n.endsWith("/" + required));
    console.log("  contains " + required.padEnd(16) + (hit ? "yes" : "NO"));
    if (!hit) process.exitCode = 1;
  }
})().catch((e) => {
  console.error("package failed: " + (e && e.stack ? e.stack : e));
  process.exit(2);
});