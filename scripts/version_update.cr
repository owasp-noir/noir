#!/usr/bin/env crystal
# noir/scripts/version_update.cr
# Update version across all files. Interactive when called without arguments.
#
# Usage:
#   crystal run scripts/version_update.cr               # Interactive prompt
#   crystal run scripts/version_update.cr -- 0.30.0     # Non-interactive
#   just version-update                                 # Interactive
#   just version-update 0.30.0                          # Non-interactive
#
# Exit codes:
#   0 - All files updated successfully (or cancelled)
#   1 - Update error or invalid input

require "./version_common"

# Update shard.yml version
def update_shard_version(new_version : String) : Bool
  content = File.read(SHARD_FILE)
  File.write(SHARD_FILE, content.gsub(/^(version:\s*)[\d.]+/m, "\\1#{new_version}"))
  true
rescue ex
  STDERR.puts "  Error updating #{SHARD_FILE}: #{ex.message}"
  false
end

# Update src/noir.cr VERSION constant
def update_noir_version(new_version : String) : Bool
  content = File.read(NOIR_FILE)
  File.write(NOIR_FILE, content.gsub(/(VERSION\s*=\s*")[\d.]+(")/, "\\1#{new_version}\\2"))
  true
rescue ex
  STDERR.puts "  Error updating #{NOIR_FILE}: #{ex.message}"
  false
end

# Update flake.nix version
def update_flake_version(new_version : String) : Bool
  content = File.read(FLAKE_FILE)
  File.write(FLAKE_FILE, content.gsub(/(version\s*=\s*")[\d.]+(")/, "\\1#{new_version}\\2"))
  true
rescue ex
  STDERR.puts "  Error updating #{FLAKE_FILE}: #{ex.message}"
  false
end

# Update Dockerfile org.opencontainers.image.version label
def update_dockerfile_version(new_version : String) : Bool
  content = File.read(DOCKERFILE)
  File.write(DOCKERFILE, content.gsub(/(org\.opencontainers\.image\.version=")[\d.]+(")/, "\\1#{new_version}\\2"))
  true
rescue ex
  STDERR.puts "  Error updating #{DOCKERFILE}: #{ex.message}"
  false
end

# Update snap/snapcraft.yaml version
def update_snapcraft_version(new_version : String) : Bool
  content = File.read(SNAPCRAFT_FILE)
  File.write(SNAPCRAFT_FILE, content.gsub(/^(version:\s*)['"]?[\d.]+['"]?/m, "\\1#{new_version}"))
  true
rescue ex
  STDERR.puts "  Error updating #{SNAPCRAFT_FILE}: #{ex.message}"
  false
end

# Update hero-badge version in a docs index file
def update_docs_index_version(path : String, new_version : String) : Bool
  content = File.read(path)
  File.write(path, content.gsub(/(class="hero-badge">)v[\d.]+(<\/)/, "\\1v#{new_version}\\2"))
  true
rescue ex
  STDERR.puts "  Error updating #{path}: #{ex.message}"
  false
end

# Update github-action/Dockerfile FROM tag
def update_action_dockerfile_version(new_version : String) : Bool
  content = File.read(ACTION_DOCKER)
  File.write(ACTION_DOCKER, content.gsub(/(FROM\s+ghcr\.io\/owasp-noir\/noir:)v?[\d.]+/, "\\1#{new_version}"))
  true
rescue ex
  STDERR.puts "  Error updating #{ACTION_DOCKER}: #{ex.message}"
  false
end

# Update github-action/README.md uses pin
def update_action_readme_version(new_version : String) : Bool
  content = File.read(ACTION_README)
  File.write(ACTION_README, content.gsub(/(uses:\s+owasp-noir\/noir@)v[\d.]+/, "\\1v#{new_version}"))
  true
rescue ex
  STDERR.puts "  Error updating #{ACTION_README}: #{ex.message}"
  false
end

# Update example version in a how_to_release doc (brew bump-formula-pr line)
def update_release_doc_version(path : String, new_version : String) : Bool
  content = File.read(path)
  File.write(path, content.gsub(/(brew bump-formula-pr --strict --version\s+)[\d.]+(\s+noir)/, "\\1#{new_version}\\2"))
  true
rescue ex
  STDERR.puts "  Error updating #{path}: #{ex.message}"
  false
end

# Update aur/PKGBUILD pkgver and reset pkgrel to 1
def update_pkgbuild_version(new_version : String) : Bool
  content = File.read(PKGBUILD_FILE)
  updated = content.gsub(/^pkgver=[\d.]+/m, "pkgver=#{new_version}")
  updated = updated.gsub(/^pkgrel=\d+/m, "pkgrel=1")
  File.write(PKGBUILD_FILE, updated)
  true
rescue ex
  STDERR.puts "  Error updating #{PKGBUILD_FILE}: #{ex.message}"
  false
end

# Show help
if ARGV.includes?("-h") || ARGV.includes?("--help")
  puts "Usage: crystal run scripts/version_update.cr [-- NEW_VERSION]"
  puts ""
  puts "Arguments:"
  puts "  NEW_VERSION    New version (e.g., 0.30.0). Prompts interactively if omitted."
  puts ""
  puts "Options:"
  puts "  -h, --help     Show this help message"
  exit 0
end

puts "=" * 50
puts "Noir Version Update Tool"
puts "=" * 50
puts

# Show current versions
entries = collect_versions
label_width = entries.max_of { |label, _, _| label.size }
puts "Current versions:"
entries.each do |label, _, version|
  puts "  #{label.ljust(label_width)}  #{version || "Not found"}"
end
puts

versions = entries.compact_map { |_, _, v| v }
unique = versions.uniq
if unique.size > 1
  puts "⚠️  Warning: Versions do not match!"
  puts "   Unique versions found: #{unique.join(", ")}"
  puts
end

current_version = get_shard_version || versions.first? || "unknown"

# Resolve new version (CLI arg wins, otherwise prompt)
args = ARGV.reject(&.starts_with?("-"))
new_version = if args.size > 0
                args[0]
              else
                print "Enter new version (or press Enter to cancel): "
                input = gets
                input.try(&.strip) || ""
              end

if new_version.empty?
  puts "Cancelled."
  exit 0
end

unless valid_version?(new_version)
  STDERR.puts "❌ Invalid version format '#{new_version}'. Expected: X.Y.Z"
  exit 1
end

if new_version == current_version
  puts "⚠️  New version matches current version. No changes made."
  exit 0
end

puts
puts "Updating to version #{new_version}..."
puts

# Each (label, path, current value, update proc)
updates = [
  {"shard.yml", SHARD_FILE, get_shard_version, -> { update_shard_version(new_version) }},
  {"src/noir.cr", NOIR_FILE, get_noir_version, -> { update_noir_version(new_version) }},
  {"flake.nix", FLAKE_FILE, get_flake_version, -> { update_flake_version(new_version) }},
  {"Dockerfile", DOCKERFILE, get_dockerfile_version, -> { update_dockerfile_version(new_version) }},
  {"snap/snapcraft.yaml", SNAPCRAFT_FILE, get_snapcraft_version, -> { update_snapcraft_version(new_version) }},
  {"docs/_index.md", DOCS_INDEX, get_docs_index_version(DOCS_INDEX), -> { update_docs_index_version(DOCS_INDEX, new_version) }},
  {"docs/_index.ko.md", DOCS_INDEX_KO, get_docs_index_version(DOCS_INDEX_KO), -> { update_docs_index_version(DOCS_INDEX_KO, new_version) }},
  {"github-action/Dockerfile", ACTION_DOCKER, get_action_dockerfile_version, -> { update_action_dockerfile_version(new_version) }},
  {"github-action/README.md", ACTION_README, get_action_readme_version, -> { update_action_readme_version(new_version) }},
  {"how_to_release/index.md", RELEASE_DOC, get_release_doc_version(RELEASE_DOC), -> { update_release_doc_version(RELEASE_DOC, new_version) }},
  {"how_to_release/index.ko.md", RELEASE_DOC_KO, get_release_doc_version(RELEASE_DOC_KO), -> { update_release_doc_version(RELEASE_DOC_KO, new_version) }},
  {"aur/PKGBUILD", PKGBUILD_FILE, get_pkgbuild_version, -> { update_pkgbuild_version(new_version) }},
]

success = 0
total = 0
updates.each do |label, _, current, fn|
  next if current.nil?
  total += 1
  print "  Updating #{label}... "
  if fn.call
    puts "✓"
    success += 1
  else
    puts "✗"
  end
end

puts
if success == total
  puts "✅ All #{success} files updated to #{new_version}"
  exit 0
else
  puts "⚠️  Updated #{success}/#{total} files"
  exit 1
end
