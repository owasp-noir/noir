#!/usr/bin/env node

// Publish-time helper (not shipped in the package). Hashes the release
// binaries listed in assets.js and writes checksums.json, which
// install.js checks every download against. The release workflow runs it
// right before `npm publish`, so the hashes are covered by npm provenance.
//
// Usage:
//   node write-checksums.js <dir>   hash the assets downloaded into <dir>
//   node write-checksums.js --check verify checksums.json is complete for
//                                   this version (runs on prepublishOnly)

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { allAssetNames } = require("./assets");

const version = require("./package.json").version;
const outFile = path.join(__dirname, "checksums.json");
const names = allAssetNames(version);

function fail(message) {
    console.error(message);
    process.exit(1);
}

const arg = process.argv[2];
if (!arg) {
    fail("Usage: node write-checksums.js <assets-dir> | --check");
}

if (arg === "--check") {
    let data;
    try {
        data = JSON.parse(fs.readFileSync(outFile, "utf8"));
    } catch {
        fail("checksums.json is missing. The release workflow generates it; see .github/workflows/publish-npm.yml.");
    }
    if (data.version !== version) {
        fail(`checksums.json is for ${data.version}, but package.json is ${version}.`);
    }
    const missing = names.filter((name) => !/^[0-9a-f]{64}$/.test(data.sha256?.[name] ?? ""));
    if (missing.length > 0) {
        fail(`checksums.json has no valid SHA-256 for: ${missing.join(", ")}`);
    }
    console.log(`checksums.json OK for ${version} (${names.length} assets).`);
    process.exit(0);
}

const sha256 = {};
for (const name of names) {
    const file = path.join(arg, name);
    if (!fs.existsSync(file)) {
        fail(`Missing release asset: ${file}`);
    }
    sha256[name] = crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
    console.log(`${sha256[name]}  ${name}`);
}

fs.writeFileSync(outFile, JSON.stringify({ version, sha256 }, null, 4) + "\n");
console.log(`Wrote ${path.relative(process.cwd(), outFile)}`);
