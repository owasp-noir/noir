#!/usr/bin/env crystal
# noir/scripts/check_version_consistency.cr
# Check version consistency across multiple files using shard.yml as source of truth
#
# Usage:
#   crystal run scripts/check_version_consistency.cr
#   just version-check
#
# Exit codes:
#   0 - All versions match
#   1 - Version mismatches detected
#   2 - Error reading files or invalid format

require "yaml"

class VersionChecker
  getter shard_version : String
  getter? quiet : Bool

  struct CheckResult
    getter file_path : String
    getter pattern : String
    getter expected : String
    getter actual : String?
    getter? matches : Bool

    def initialize(@file_path : String, @pattern : String, @expected : String, @actual : String?, @matches : Bool)
    end
  end

  def initialize(@quiet : Bool = false)
    @shard_version = read_shard_version
  end

  def run : Int32
    puts "Checking version consistency across files..." unless quiet?
    puts "Source of truth: shard.yml version = #{@shard_version}" unless quiet?
    puts unless quiet?

    results = [] of CheckResult

    # Check each file
    results << check_flake_nix
    results << check_dockerfile
    results << check_noir_cr
    results << check_sarif_cr
    results << check_snapcraft_yaml
    results << check_docs_index_md
    results << check_docs_index_ko_md
    results << check_github_action_dockerfile
    results << check_github_action_readme
    results << check_sarif_spec
    results << check_copilot_instructions
    results << check_how_to_release_md
    results << check_how_to_release_ko_md

    # Print results
    mismatches = [] of CheckResult
    results.each do |result|
      if result.matches?
        puts "✅ #{result.file_path}" unless quiet?
      else
        puts "❌ #{result.file_path}" unless quiet?
        puts "   Expected: #{result.expected}" unless quiet?
        puts "   Found: #{result.actual || "NOT FOUND"}" unless quiet?
        mismatches << result
      end
    end

    puts unless quiet?
    if mismatches.empty?
      puts "🎉 All versions match! (#{@shard_version})" unless quiet?
      0
    else
      puts "❌ Version mismatch detected in #{mismatches.size} file(s):" unless quiet?
      mismatches.each do |r|
        puts "  - #{r.file_path}" unless quiet?
      end
      1
    end
  end

  private def read_shard_version : String
    shard_yml = YAML.parse(File.read("shard.yml"))
    shard_yml["version"].as_s
  rescue ex
    STDERR.puts "Error reading version from shard.yml: #{ex.message}"
    exit 2
  end

  private def check_file(file_path : String, pattern : Regex, expected_version : String) : CheckResult
    if File.exists?(file_path)
      content = File.read(file_path)
      if match = content.match(pattern)
        actual = match[1]
        CheckResult.new(file_path, pattern.source, expected_version, actual, actual == expected_version)
      else
        CheckResult.new(file_path, pattern.source, expected_version, nil, false)
      end
    else
      CheckResult.new(file_path, pattern.source, expected_version, nil, false)
    end
  rescue ex
    STDERR.puts "Error checking #{file_path}: #{ex.message}"
    CheckResult.new(file_path, pattern.source, expected_version, nil, false)
  end

  private def check_flake_nix : CheckResult
    check_file("flake.nix", /version\s*=\s*"([^"]+)"/, @shard_version)
  end

  private def check_dockerfile : CheckResult
    check_file("Dockerfile", /org\.opencontainers\.image\.version="([^"]+)"/, @shard_version)
  end

  private def check_noir_cr : CheckResult
    check_file("src/noir.cr", /VERSION\s*=\s*"([^"]+)"/, @shard_version)
  end

  private def check_sarif_cr : CheckResult
    # Match the tool version in the driver section, not the SARIF schema version
    # Look for "driver" followed by "name" and "version" fields
    check_file("src/output_builder/sarif.cr", /"driver".*?"name",\s*"OWASP Noir".*?"version",\s*"([^"]+)"/m, @shard_version)
  end

  private def check_snapcraft_yaml : CheckResult
    check_file("snap/snapcraft.yaml", /^version:\s*([\d.]+)\s*$/m, @shard_version)
  end

  private def check_docs_index_file(file_path : String) : CheckResult
    # Check both version and badge fields in documentation index files
    expected = "v#{@shard_version}"

    if File.exists?(file_path)
      content = File.read(file_path)
      version_match = content.match(/version\s*=\s*"v([^"]+)"/)
      badge_match = content.match(/badge\s*=\s*"v([^"]+)"/)

      if version_match && badge_match
        version_value = "v#{version_match[1]}"
        badge_value = "v#{badge_match[1]}"

        if version_value == expected && badge_value == expected
          CheckResult.new(file_path, "version and badge", expected, expected, true)
        else
          actual = "version=#{version_value}, badge=#{badge_value}"
          CheckResult.new(file_path, "version and badge", expected, actual, false)
        end
      else
        CheckResult.new(file_path, "version and badge", expected, nil, false)
      end
    else
      CheckResult.new(file_path, "version and badge", expected, nil, false)
    end
  end

  private def check_docs_index_md : CheckResult
    check_docs_index_file("docs/content/_index.md")
  end

  private def check_docs_index_ko_md : CheckResult
    check_docs_index_file("docs/content/_index.ko.md")
  end

  private def check_github_action_dockerfile : CheckResult
    check_file("github-action/Dockerfile", /FROM\s+ghcr\.io\/owasp-noir\/noir:v([^\s]+)/, @shard_version)
  end

  private def check_github_action_readme : CheckResult
    check_file("github-action/README.md", /uses:\s+owasp-noir\/noir@v([\d.]+)/, @shard_version)
  end

  private def check_sarif_spec : CheckResult
    check_file("spec/unit_test/output_builder/sarif_spec.cr", /tool\["version"\]\.as_s\.should\s+eq\("([^"]+)"\)/, @shard_version)
  end

  private def check_copilot_instructions : CheckResult
    check_file(".github/copilot-instructions.md", /shard\.yml.*version:\s*([^\)]+)\)/, @shard_version)
  end

  private def check_how_to_release_md : CheckResult
    # Check for example version in brew command
    check_file("docs/content/development/how_to_release/index.md", /brew bump-formula-pr --strict --version\s+([\d.]+)\s+noir/, @shard_version)
  end

  private def check_how_to_release_ko_md : CheckResult
    # Check for example version in brew command
    check_file("docs/content/development/how_to_release/index.ko.md", /brew bump-formula-pr --strict --version\s+([\d.]+)\s+noir/, @shard_version)
  end
end

# Entry point
quiet = ARGV.includes?("-q") || ARGV.includes?("--quiet")
show_help = ARGV.includes?("-h") || ARGV.includes?("--help")

if show_help
  puts "Usage: crystal run scripts/check_version_consistency.cr [options]"
  puts ""
  puts "Options:"
  puts "  -q, --quiet    Suppress detailed output"
  puts "  -h, --help     Show this help message"
  puts ""
  puts "Description:"
  puts "  Checks version consistency across all files using shard.yml as source of truth."
  puts ""
  puts "Exit codes:"
  puts "  0 - All versions match"
  puts "  1 - Version mismatches detected"
  puts "  2 - Error reading files"
  exit 0
end

checker = VersionChecker.new(quiet)
exit_code = checker.run
exit(exit_code)
