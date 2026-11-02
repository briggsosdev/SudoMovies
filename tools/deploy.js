// Deploy the channel to a Roku device over the dev server.
//
// Usage: node tools/deploy.js [host] [port]
//
// Only the packaged scope is sent (manifest, source, components, images);
// tests, tools, node_modules and out are never part of a channel.
const { deploy } = require("roku-deploy");

const host = process.argv[2] || process.env.ROKU_HOST || "";
const port = Number(process.argv[3] || 8060);

const options = {
  host,
  port,
  rootDir: require("node:path").resolve(__dirname, ".."),
  password: "",
  progressBar: false,
  failFast: true,
};

if (!host) {
  console.error("No host supplied. Pass a host arg or set ROKU_HOST.");
  process.exit(2);
}
console.log(`--- deploying to ${host}:${port} ---`);
console.log("    scope: roku-deploy defaults (manifest, source, components, images, locale)");
console.log("    note : tests/, tools/, out/ and node_modules/ are not in the default set");

deploy(options)
  .then((result) => {
    console.log("--- result ---");
    if (result && result.message) console.log("  status : " + result.message);
    if (result && result.success !== undefined) console.log("  success: " + result.success);
    const id = result && (result.sideloaded_id || result.sideloadedId);
    if (id) console.log("  sideloaded id: " + id);
  })
  .catch((error) => {
    console.log("DEPLOY FAILED");
    console.log("  " + (error && error.message ? error.message : error));
    process.exitCode = 1;
  });