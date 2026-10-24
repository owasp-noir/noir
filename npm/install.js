#!/usr/bin/env node

// npm postinstall: downloads the Noir release binary for this platform,
// checks it against the SHA-256 pinned in checksums.json at publish time,
// and unpacks it into npm/dist/. The `noir` command (npm/noir.js) runs it
// from there.
//
// The macOS binary loads its dylibs from @executable_path/lib, so the
// tarball's lib/ must stay next to it.

const { execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { getAsset } = require("./assets");

const version = require("../package.json").version;
const distDir = path.join(__dirname, "dist");

function loadChecksums() {
    let data;
    try {
        data = require("./checksums.json");
    } catch {
        throw new Error(
            "npm/checksums.json is missing, so the download can't be verified. " +
            "Published packages always include it; for a local build, run " +
            "`node npm/write-checksums.js <dir-with-release-assets>` first."
        );
    }
    if (data.version !== version) {
        throw new Error(`npm/checksums.json is for ${data.version}, but this package is ${version}.`);
    }
    return data.sha256;
}

async function download(url) {
    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`Download failed (${response.status}): ${url}`);
    }
    return Buffer.from(await response.arrayBuffer());
}

(async () => {
    const asset = getAsset(version, process.platform, process.arch);
    if (!asset) {
        throw new Error(
            `Unsupported platform: ${process.platform} ${process.arch}. ` +
            "See https://owasp-noir.github.io/noir/get_started/installation/ for other install options."
        );
    }

    const expected = loadChecksums()[asset.name];
    if (!expected) {
        throw new Error(`npm/checksums.json has no entry for ${asset.name}.`);
    }

    const url = `https://github.com/owasp-noir/noir/releases/download/v${version}/${asset.name}`;
    console.log(`Downloading ${asset.name}...`);
    const data = await download(url);

    // Verify before touching npm/dist/, so a bad download never replaces a good install.
    const actual = crypto.createHash("sha256").update(data).digest("hex");
    if (actual !== expected) {
        throw new Error(
            `Checksum mismatch for ${asset.name}; refusing to install.\n` +
            `  expected ${expected}\n  got      ${actual}`
        );
    }

    // Start from an empty dist/ so a reinstall never mixes files from two versions.
    fs.rmSync(distDir, { recursive: true, force: true });
    fs.mkdirSync(distDir, { recursive: true });

    if (asset.tarball) {
        const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "noir-npm-"));
        const archive = path.join(tmpDir, asset.name);
        try {
            fs.writeFileSync(archive, data);
            execFileSync("tar", ["-xzf", archive, "-C", distDir], { stdio: "inherit" });
        } finally {
            fs.rmSync(tmpDir, { recursive: true, force: true });
        }
    } else {
        fs.writeFileSync(path.join(distDir, "noir"), data);
    }

    const binary = path.join(distDir, "noir");
    if (!fs.existsSync(binary)) {
        throw new Error(`Downloaded ${asset.name} but ${binary} is missing`);
    }
    fs.chmodSync(binary, 0o755);

    console.log(`Noir ${version} installed (SHA-256 verified).`);
})().catch((err) => {
    console.error(err.message);
    process.exit(1);
});
