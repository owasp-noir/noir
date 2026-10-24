#!/usr/bin/env node

// `noir` command for the npm package. Runs the binary that install.js
// downloaded, by its real path, so the macOS build finds its bundled lib/.

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const binary = path.join(__dirname, "dist", "noir");

if (!fs.existsSync(binary)) {
    console.error(
        "Noir binary not found. It is downloaded when the package installs; " +
        "if install scripts were skipped, run `npm rebuild @owasp-noir/noir` " +
        "(pnpm: `pnpm approve-builds`)"
    );
    process.exit(1);
}

const result = spawnSync(binary, process.argv.slice(2), { stdio: "inherit" });

if (result.error) {
    console.error(result.error.message);
    process.exit(1);
}
if (result.signal) {
    process.kill(process.pid, result.signal);
}
process.exit(result.status ?? 1);
