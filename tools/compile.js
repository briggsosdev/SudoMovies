/*
 * Full-channel compile + diagnostics using brighterscript, the official Roku
 * language toolchain.
 *
 * Why this exists: the earlier ad-hoc regex syntax pass reported "clean" on
 * every file, yet it does not understand includes, scopes, or types. It is
 * structurally incapable of finding the bugs that actually break a channel.
 * brighterscript resolves the include graph, builds scopes, and type-checks
 * exactly like the Roku build server does.
 *
 * Usage: node tools/compile.js
 * Exit code 0 = no errors.
 */
const path = require("path");
const fs = require("fs");

const ROOT = path.resolve(__dirname, "..");

(async () => {
  let bs;
  try {
    bs = require("brighterscript");
  } catch (e) {
    console.error("brighterscript not installed. Run: npm install --save-dev brighterscript");
    process.exit(2);
  }

  // brighterscript 0.73.x: `new Program()` + `validate()` no longer globs or
  // parse files on their own -- the CLI drives that through ProgramBuilder.
  // Use the builder so the include graph and scopes are actually resolved.
  const builder = new bs.ProgramBuilder();
  await builder.run({
    cwd: ROOT,
    rootDir: ROOT,
    manifestPath: "manifest",
    // Exclude tests: they live outside components/ so they are never packaged
    // and never compiled into a shipped component.
    files: [
      "manifest",
      "components/**/*.brs",
      "components/**/*.xml",
      "source/**/*.brs",
    ],
    staging: false,
    deploy: false,
    watch: false,
    createPackage: false,
    logLevel: "error",
    showDiagnosticsInConsole: false,
  });

  const program = builder.program;
  if (!program) {
    console.error("compile harness failed: no program built");
    process.exit(2);
  }

  const diags = program.getDiagnostics();
  const errors = diags.filter((d) => d.severity === bs.DiagnosticSeverity.Error);
  const warnings = diags.filter((d) => d.severity === bs.DiagnosticSeverity.Warning);

  const rel = (p) => {
    if (!p) return "?";
    const abs = p.startsWith?.(ROOT) ? p : path.join(ROOT, p || "");
    return path.relative(ROOT, abs) || p;
  };

  const show = (list, label) => {
    if (!list.length) {
      console.log(label + ": none");
      console.log("");
      return;
    }
    console.log(label + ": " + list.length);
    for (const d of list) {
      const loc = d.location ? "  line " + (d.location.line + 1) + ":" + (d.location.column + 1) : "";
      const file = d.filePath ? rel(d.filePath) : d.file?.pkgPath || "?";
      console.log("  [" + (d.code || "?") + "] " + file + loc);
      console.log("      " + String(d.message).split("\n").join("\n      "));
    }
    console.log("");
  };

  console.log("=== COMPILATION ===");
  show(errors, "ERRORS");
  show(warnings, "WARNINGS");

  // Files that will actually ship in the package.
  const emitted = Object.keys(program.pkgMap || {}).length;
  console.log("files in package: " + emitted);

  // Encoding corruption scan. A U+FFFD means the file was written through a
  // lossy codepage and characters are already gone; it cannot be recovered by
  // fixing the encoding later, only by rewriting the text.
  const suspect = [];
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (["node_modules", "out", ".git"].includes(e.name)) continue;
        walk(full);
      } else if (/\.(brs|xml)$/i.test(e.name)) {
        const raw = fs.readFileSync(full, "utf8");
        if (raw.includes("\uFFFD")) {
          const lines = raw.split(/\r?\n/);
          const hits = [];
          lines.forEach((l, i) => {
            if (l.includes("\uFFFD")) hits.push(i + 1);
          });
          suspect.push(path.relative(ROOT, full) + "  lines: " + hits.slice(0, 12).join(",") + (hits.length > 12 ? " (+" + (hits.length - 12) + ")" : ""));
        }
      }
    }
  };
  walk(ROOT);
  console.log("");
  console.log("=== ENCODING CORRUPTION (U+FFFD) ===");
  if (!suspect.length) console.log("none");
  else for (const s of suspect) console.log("  " + s);

  console.log("");
  console.log("=== SUMMARY ===");
  console.log("errors=" + errors.length + " warnings=" + warnings.length + " corruptFiles=" + suspect.length);
  process.exit(errors.length ? 1 : 0);
})().catch((e) => {
  console.error("compile harness failed: " + (e && e.stack ? e.stack : e));
  process.exit(2);
});