#!/usr/bin/env node

// For NPM publishing purposes

const fs = require("fs");
const path = require("path");

const version = require("./package.json").version;

const platform = process.platform;
const arch = process.arch;

function getAssetName() {
    if (platform === "linux" && arch === "x64") {
        return `noir-v${version}-linux-x86_64`;
    }

    if (platform === "linux" && arch === "arm64") {
        return `noir-v${version}-linux-arm64`;
    }

    if (platform === "darwin" && arch === "arm64") {
        return `noir-v${version}-osx-arm64`;
    }

    if (platform === "darwin" && arch === "x64") {
        return `noir-v${version}-osx-x86_64`;
    }

    throw new Error(`Unsupported platform: ${platform} ${arch}`);
}

(async () => {
    const asset = getAssetName();

    const downloadUrl =
        `https://github.com/owasp-noir/noir/releases/download/v${version}/${asset}`;

    const binDir = path.join(__dirname, "bin");
    const output = path.join(binDir, "noir");

    fs.mkdirSync(binDir, { recursive: true });

    console.log(`Downloading ${asset}...`);

    const response = await fetch(downloadUrl);

    if (!response.ok) {
        throw new Error(`Download failed (${response.status})`);
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    fs.writeFileSync(output, buffer);
    fs.chmodSync(output, 0o755);

    console.log("Binary installed.");
})().catch((err) => {
    console.error(err.message);
    process.exit(1);
});