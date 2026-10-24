// Release binaries the npm package can install, keyed by Node's
// `${process.platform}-${process.arch}`. Shared by install.js (download and
// verify) and write-checksums.js (hash at publish time) so the two can't drift.
//
//   Linux  noir-vX.Y.Z-linux-{x86_64,arm64}          plain binary
//   macOS  noir-vX.Y.Z-osx-{x86_64,arm64}.tar.gz     noir + lib/*.dylib

const ASSETS = {
    "linux-x64": { suffix: "linux-x86_64", tarball: false },
    "linux-arm64": { suffix: "linux-arm64", tarball: false },
    "darwin-x64": { suffix: "osx-x86_64.tar.gz", tarball: true },
    "darwin-arm64": { suffix: "osx-arm64.tar.gz", tarball: true },
};

// The asset for one platform, or null when there is no prebuilt binary.
function getAsset(version, platform, arch) {
    const asset = ASSETS[`${platform}-${arch}`];
    if (!asset) return null;
    return { name: `noir-v${version}-${asset.suffix}`, tarball: asset.tarball };
}

function allAssetNames(version) {
    return Object.values(ASSETS).map((asset) => `noir-v${version}-${asset.suffix}`);
}

module.exports = { getAsset, allAssetNames };
