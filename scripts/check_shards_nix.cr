#!/usr/bin/env crystal
# noir/scripts/check_shards_nix.cr
# Check that shards.nix still matches shard.lock.
#
# `shards.nix` is generated (`just nix-update`, i.e. crystal2nix) and pins every
# dependency for the Nix build by git rev + hash. Nothing regenerates it
# automatically, so adding, dropping, or bumping a shard silently leaves the
# Nix package building yesterday's dependency set — or failing outright on a
# dependency that is not in the file at all.
#
# Usage:
#   crystal run scripts/check_shards_nix.cr
#   just nix-check
#
# Exit codes:
#   0 - shards.nix matches shard.lock
#   1 - drift detected (regenerate with `just nix-update`)

require "yaml"

LOCK_FILE  = "shard.lock"
SHARDS_NIX = "shards.nix"

record NixShard, url : String, rev : String, sha256 : String

# Parse the generated attribute set. crystal2nix emits one flat block per
# shard, either as `url`/`rev`/`sha256` (fetchgit) or `owner`/`repo`/`rev`/
# `sha256` (fetchFromGitHub); no block nests braces, so a non-greedy scan is
# enough and saves pulling a Nix parser into a stdlib-only script.
def parse_shards_nix(source : String) : Hash(String, NixShard)
  result = {} of String => NixShard

  source.scan(/"([^"]+)"\s*=\s*\{([^}]*)\}/m) do |match|
    name = match[1]
    body = match[2]

    field = ->(key : String) {
      m = body.match(/\b#{key}\s*=\s*"([^"]*)"/)
      m ? m[1] : ""
    }

    url = field.call("url")
    if url.empty?
      owner = field.call("owner")
      repo = field.call("repo")
      url = "https://github.com/#{owner}/#{repo}.git" unless owner.empty? || repo.empty?
    end

    result[name] = NixShard.new(url, field.call("rev"), field.call("sha256"))
  end

  result
end

record LockShard, url : String, version : String

def parse_shard_lock(source : String) : Hash(String, LockShard)
  result = {} of String => LockShard

  shards = YAML.parse(source)["shards"]?
  return result unless shards

  shards.as_h.each do |name, entry|
    fields = entry.as_h
    # Every resolver shards supports writes the repository under its own key
    # (`git`, `hg`, `fossil`); take whichever is present rather than assuming.
    url = %w[git hg fossil].compact_map { |key| fields[key]?.try(&.as_s) }.first?
    result[name.as_s] = LockShard.new(url || "", fields["version"]?.try(&.as_s) || "")
  end

  result
end

# The lock records a tag as a bare version; crystal2nix writes back whatever
# the repository actually tags, which is `vX.Y.Z` for most shards and `X.Y.Z`
# for some. A dependency pinned to a branch instead of a release is locked as
# `X.Y.Z+git.commit.<sha>`, and then the rev has to be that commit.
def rev_matches?(rev : String, version : String) : Bool
  if commit = version.match(/\+git\.commit\.([0-9a-f]+)/)
    return rev.starts_with?(commit[1])
  end

  rev == version || rev == "v#{version}"
end

unless File.exists?(LOCK_FILE) && File.exists?(SHARDS_NIX)
  puts "❌ Missing #{File.exists?(LOCK_FILE) ? SHARDS_NIX : LOCK_FILE}"
  exit 1
end

lock = parse_shard_lock(File.read(LOCK_FILE))
nix = parse_shards_nix(File.read(SHARDS_NIX))

if lock.empty?
  puts "❌ No shards found in #{LOCK_FILE}. Fix scripts/check_shards_nix.cr."
  exit 1
end

problems = [] of String

(lock.keys - nix.keys).sort!.each do |name|
  problems << "#{name}: in #{LOCK_FILE} but missing from #{SHARDS_NIX}"
end

(nix.keys - lock.keys).sort!.each do |name|
  problems << "#{name}: in #{SHARDS_NIX} but no longer in #{LOCK_FILE}"
end

label_width = lock.keys.max_of(&.size)

puts "Pinned dependencies:"
lock.keys.sort!.each do |name|
  locked = lock[name]
  pinned = nix[name]?
  puts "  #{name.ljust(label_width)}  #{locked.version.ljust(12)} #{pinned ? pinned.rev : "not pinned"}"

  next unless pinned

  unless rev_matches?(pinned.rev, locked.version)
    problems << "#{name}: locked at #{locked.version} but pinned at rev #{pinned.rev.empty? ? "(none)" : pinned.rev}"
  end

  if !locked.url.empty? && !pinned.url.empty? && locked.url != pinned.url
    problems << "#{name}: locked from #{locked.url} but pinned from #{pinned.url}"
  end

  problems << "#{name}: pinned without a sha256" if pinned.sha256.empty?
end
puts

if problems.empty?
  puts "✅ #{SHARDS_NIX} matches #{LOCK_FILE} (#{lock.size} shards)"
  exit 0
end

puts "❌ #{SHARDS_NIX} is out of date:"
problems.each { |problem| puts "     - #{problem}" }
puts
puts "   Regenerate it with 'just nix-update' and commit the result."
exit 1
