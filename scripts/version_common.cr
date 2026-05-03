require "yaml"

# Version file locations (shard.yml is the source of truth)
SHARD_FILE     = "shard.yml"
NOIR_FILE      = "src/noir.cr"
FLAKE_FILE     = "flake.nix"
DOCKERFILE     = "Dockerfile"
SNAPCRAFT_FILE = "snap/snapcraft.yaml"
DOCS_INDEX     = "docs/content/_index.md"
DOCS_INDEX_KO  = "docs/content/_index.ko.md"
ACTION_DOCKER  = "github-action/Dockerfile"
ACTION_README  = "github-action/README.md"
RELEASE_DOC    = "docs/content/development/how_to_release/index.md"
RELEASE_DOC_KO = "docs/content/development/how_to_release/index.ko.md"
PKGBUILD_FILE  = "aur/PKGBUILD"

# Extract version from shard.yml
def get_shard_version : String?
  YAML.parse(File.read(SHARD_FILE))["version"].as_s
rescue
  nil
end

# Extract VERSION from src/noir.cr
def get_noir_version : String?
  match = File.read(NOIR_FILE).match(/VERSION\s*=\s*"([^"]+)"/)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from flake.nix
def get_flake_version : String?
  match = File.read(FLAKE_FILE).match(/version\s*=\s*"([^"]+)"/)
  match ? match[1] : nil
rescue
  nil
end

# Extract org.opencontainers.image.version from Dockerfile
def get_dockerfile_version : String?
  match = File.read(DOCKERFILE).match(/org\.opencontainers\.image\.version="([^"]+)"/)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from snap/snapcraft.yaml
def get_snapcraft_version : String?
  YAML.parse(File.read(SNAPCRAFT_FILE))["version"].to_s
rescue
  nil
end

# Extract hero-badge version from a docs index file
def get_docs_index_version(path : String) : String?
  match = File.read(path).match(/class="hero-badge">v([\d.]+)</)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from github-action/Dockerfile
def get_action_dockerfile_version : String?
  match = File.read(ACTION_DOCKER).match(/FROM\s+ghcr\.io\/owasp-noir\/noir:v([\d.]+)/)
  match ? match[1] : nil
rescue
  nil
end

# Extract version from github-action/README.md
def get_action_readme_version : String?
  match = File.read(ACTION_README).match(/uses:\s+owasp-noir\/noir@v([\d.]+)/)
  match ? match[1] : nil
rescue
  nil
end

# Extract example version from a how_to_release doc (brew bump-formula-pr line)
def get_release_doc_version(path : String) : String?
  match = File.read(path).match(/brew bump-formula-pr --strict --version\s+([\d.]+)\s+noir/)
  match ? match[1] : nil
rescue
  nil
end

# Extract pkgver from aur/PKGBUILD
def get_pkgbuild_version : String?
  match = File.read(PKGBUILD_FILE).match(/^pkgver=([\d.]+)/m)
  match ? match[1] : nil
rescue
  nil
end

# Collect (label, path, version) for every tracked file.
def collect_versions : Array(Tuple(String, String, String?))
  [
    {"shard.yml", SHARD_FILE, get_shard_version},
    {"src/noir.cr", NOIR_FILE, get_noir_version},
    {"flake.nix", FLAKE_FILE, get_flake_version},
    {"Dockerfile", DOCKERFILE, get_dockerfile_version},
    {"snap/snapcraft.yaml", SNAPCRAFT_FILE, get_snapcraft_version},
    {"docs/_index.md", DOCS_INDEX, get_docs_index_version(DOCS_INDEX)},
    {"docs/_index.ko.md", DOCS_INDEX_KO, get_docs_index_version(DOCS_INDEX_KO)},
    {"github-action/Dockerfile", ACTION_DOCKER, get_action_dockerfile_version},
    {"github-action/README.md", ACTION_README, get_action_readme_version},
    {"docs/.../how_to_release/index.md", RELEASE_DOC, get_release_doc_version(RELEASE_DOC)},
    {"docs/.../how_to_release/index.ko.md", RELEASE_DOC_KO, get_release_doc_version(RELEASE_DOC_KO)},
    {"aur/PKGBUILD", PKGBUILD_FILE, get_pkgbuild_version},
  ]
end

# Validate semver-like version (X.Y.Z)
def valid_version?(version : String) : Bool
  !!(version =~ /^\d+\.\d+\.\d+$/)
end
