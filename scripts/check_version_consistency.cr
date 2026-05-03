#!/usr/bin/env crystal
# noir/scripts/check_version_consistency.cr
# Check version consistency across multiple files using shard.yml as source of truth.
#
# Usage:
#   crystal run scripts/check_version_consistency.cr
#   just version-check
#
# Exit codes:
#   0 - All versions match
#   1 - Version mismatches detected

require "./version_common"

entries = collect_versions

label_width = entries.max_of { |label, _, _| label.size }

puts "Current versions:"
entries.each do |label, _, version|
  puts "  #{label.ljust(label_width)}  #{version || "Not found"}"
end
puts

versions = entries.compact_map { |_, _, v| v }
if versions.empty?
  puts "No versions found!"
  exit 1
end

unique = versions.uniq
if unique.size == 1
  puts "✅ All versions match: #{unique.first}"
  exit 0
else
  puts "❌ Versions do not match!"
  puts "   Unique versions found: #{unique.join(", ")}"
  puts
  shard_v = get_shard_version
  if shard_v
    puts "   Source of truth (shard.yml): #{shard_v}"
    mismatches = entries.reject { |_, _, v| v.nil? || v == shard_v }
    unless mismatches.empty?
      puts "   Mismatched files:"
      mismatches.each do |label, _, v|
        puts "     - #{label} (#{v})"
      end
    end
  end
  exit 1
end
