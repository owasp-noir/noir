#!/usr/bin/env crystal
# noir/scripts/version_update.cr
# Update version across all files using shard.yml as source of truth
#
# Usage:
#   crystal run scripts/version_update.cr              # Update all files to shard.yml version
#   crystal run scripts/version_update.cr -- 0.29.0    # Set new version in shard.yml and all files
#   just version-update                                # Update all files to shard.yml version
#   just version-update 0.29.0                         # Set new version everywhere
#
# Exit codes:
#   0 - All files updated successfully
#   1 - Error during update
#   2 - Error reading files or invalid format

require "yaml"

class VersionUpdater
  # Each replacement target: file path, regex pattern, replacement template.
  # The template uses `%{version}` for bare version and `%{v_version}` for "v"-prefixed.
  record Target,
    file_path : String,
    pattern : Regex,
    replacement : String

  TARGETS = [
    Target.new(
      "shard.yml",
      /^(version:\s*)[\d.]+/m,
      "\\1%{version}"
    ),
    Target.new(
      "src/noir.cr",
      /(VERSION\s*=\s*")[\d.]+(")/ ,
      "\\1%{version}\\2"
    ),
    Target.new(
      "flake.nix",
      /(version\s*=\s*")[\d.]+(")/ ,
      "\\1%{version}\\2"
    ),
    Target.new(
      "Dockerfile",
      /(org\.opencontainers\.image\.version=")[\d.]+(")/ ,
      "\\1%{version}\\2"
    ),
    Target.new(
      "snap/snapcraft.yaml",
      /^(version:\s*)[\d.]+/m,
      "\\1%{version}"
    ),
    Target.new(
      "docs/content/_index.md",
      /(class="hero-badge">)v[\d.]+(<\/)/,
      "\\1%{v_version}\\2"
    ),
    Target.new(
      "docs/content/_index.ko.md",
      /(class="hero-badge">)v[\d.]+(<\/)/,
      "\\1%{v_version}\\2"
    ),
    Target.new(
      "github-action/Dockerfile",
      /(FROM\s+ghcr\.io\/owasp-noir\/noir:)v[\d.]+/,
      "\\1%{v_version}"
    ),
    Target.new(
      "github-action/README.md",
      /(uses:\s+owasp-noir\/noir@)v[\d.]+/,
      "\\1%{v_version}"
    ),
    Target.new(
      "docs/content/development/how_to_release/index.md",
      /(brew bump-formula-pr --strict --version\s+)[\d.]+(\s+noir)/,
      "\\1%{version}\\2"
    ),
    Target.new(
      "docs/content/development/how_to_release/index.ko.md",
      /(brew bump-formula-pr --strict --version\s+)[\d.]+(\s+noir)/,
      "\\1%{version}\\2"
    ),
  ]

  getter version : String

  def initialize(@version : String)
  end

  def run : Int32
    puts "Updating version to #{@version} across all files...\n"

    errors = [] of String

    TARGETS.each do |target|
      result = update_file(target)
      if result
        puts "  ✅ #{target.file_path}"
      else
        puts "  ❌ #{target.file_path}"
        errors << target.file_path
      end
    end

    puts
    if errors.empty?
      puts "🎉 All files updated to #{@version}!"
      0
    else
      puts "❌ Failed to update #{errors.size} file(s):"
      errors.each { |f| puts "  - #{f}" }
      1
    end
  end

  private def update_file(target : Target) : Bool
    unless File.exists?(target.file_path)
      STDERR.puts "  Warning: #{target.file_path} not found, skipping"
      return false
    end

    content = File.read(target.file_path)
    unless content.match(target.pattern)
      STDERR.puts "  Warning: pattern not found in #{target.file_path}"
      return false
    end

    replacement = target.replacement
      .gsub("%{version}", @version)
      .gsub("%{v_version}", "v#{@version}")

    new_content = content.gsub(target.pattern, replacement)
    if new_content != content
      File.write(target.file_path, new_content)
    end
    true
  rescue ex
    STDERR.puts "  Error updating #{target.file_path}: #{ex.message}"
    false
  end
end

def read_shard_version : String
  shard_yml = YAML.parse(File.read("shard.yml"))
  shard_yml["version"].as_s
rescue ex
  STDERR.puts "Error reading version from shard.yml: #{ex.message}"
  exit 2
end

# Entry point
show_help = ARGV.includes?("-h") || ARGV.includes?("--help")

if show_help
  puts "Usage: crystal run scripts/version_update.cr [-- NEW_VERSION]"
  puts ""
  puts "Arguments:"
  puts "  NEW_VERSION    New version to set (e.g., 0.29.0)"
  puts "                 If omitted, uses current shard.yml version"
  puts ""
  puts "Options:"
  puts "  -h, --help     Show this help message"
  puts ""
  puts "Description:"
  puts "  Updates version across all project files using shard.yml as source of truth."
  puts "  If NEW_VERSION is provided, shard.yml is updated first, then all other files."
  exit 0
end

args = ARGV.reject { |a| a.starts_with?("-") }
if args.size > 0
  new_version = args[0]
  unless new_version.matches?(/^\d+\.\d+\.\d+$/)
    STDERR.puts "Error: Invalid version format '#{new_version}'. Expected: X.Y.Z"
    exit 2
  end
  version = new_version
else
  version = read_shard_version
end

updater = VersionUpdater.new(version)
exit_code = updater.run
exit(exit_code)
