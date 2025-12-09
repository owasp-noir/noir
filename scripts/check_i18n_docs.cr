#!/usr/bin/env crystal
# noir/scripts/check_i18n_docs.cr
# Check for missing i18n documentation files
# Supports multiple languages via CLI flags or NOIR_I18N_LANGS env var
#
# Usage:
#   crystal run scripts/check_i18n_docs.cr -- [options]
#   just docs-i18n-check
#
# Examples:
#   crystal run scripts/check_i18n_docs.cr -- -l ko,ja
#   crystal run scripts/check_i18n_docs.cr -- -l ko -l ja -b docs/content
#   NOIR_I18N_LANGS=ko,ja crystal run scripts/check_i18n_docs.cr
#
# Exit codes:
#   0 - No missing translations OR --no-fail provided
#   1 - Missing translations detected (default behavior)
#   2 - Invalid options

require "option_parser"
require "json"

# file_utils not required

class I18nDocsChecker
  getter base_path : String
  getter languages : Array(String)
  getter? quiet
  getter format : String
  getter? fail_on_missing

  struct LangResult
    getter language : String
    getter total_files : Int32
    getter missing_files : Array(String)
    getter found_files : Array(String)

    def initialize(@language : String, @total_files : Int32, @missing_files : Array(String), @found_files : Array(String))
    end

    def missing_count : Int32
      @missing_files.size
    end

    def found_count : Int32
      @found_files.size
    end

    def to_json(builder : JSON::Builder)
      builder.object do
        builder.field "language", @language
        builder.field "total_files", @total_files
        builder.field "found_count", found_count
        builder.field "missing_count", missing_count
        builder.field "missing_files" do
          builder.array do
            @missing_files.each { |f| builder.string f }
          end
        end
        builder.field "found_files" do
          builder.array do
            @found_files.each { |f| builder.string f }
          end
        end
      end
    end
  end

  def initialize(
    @base_path : String = "docs/content",
    @languages : Array(String) = ["ko"],
    @quiet : Bool = false,
    @format : String = "text",
    @fail_on_missing : Bool = true,
  )
  end

  def run : Int32
    puts "Checking documentation translations..." unless quiet? || format == "json"
    puts "Base path: #{@base_path}" unless quiet? || format == "json"
    puts "Languages: #{languages.join(", ")}" unless quiet? || format == "json"
    puts unless quiet? || format == "json"

    index_files = find_index_files(@base_path)
    if index_files.empty?
      puts "Warning: No index.md or _index.md files found under '#{@base_path}'" unless format == "json"
    end

    results = [] of LangResult

    @languages.each do |lang|
      missing = [] of String
      found = [] of String
      index_files.each do |file_path|
        translated = translated_file_path(file_path, lang)
        if File.exists?(translated)
          found << translated
          puts "✅ [#{lang}] Found: #{translated}" unless quiet? || format == "json"
        else
          missing << translated
          puts "❌ [#{lang}] Missing: #{translated}" unless quiet? || format == "json"
        end
      end
      results << LangResult.new(lang, index_files.size, missing, found)
      puts unless quiet? || format == "json"
    end

    print_summary(index_files.size, results)

    any_missing = results.any? { |r| r.missing_count > 0 }
    if fail_on_missing? && any_missing
      1
    else
      0
    end
  end

  private def print_summary(total_files : Int32, results : Array(LangResult))
    case @format
    when "json"
      builder = JSON::Builder.new(STDOUT)
      builder.object do
        builder.field "base_path", @base_path
        builder.field "languages" do
          builder.array { @languages.each { |l| builder.string l } }
        end
        builder.field "total_docs", total_files
        builder.field "per_language" do
          builder.array do
            results.each(&.to_json(builder))
          end
        end
        builder.field "ok", !results.any? { |r| r.missing_count > 0 }
      end
      puts
    else
      puts
      puts "Summary:"
      puts "  Base path: #{@base_path}"
      puts "  Languages: #{@languages.join(", ")}"
      puts "  Total documentation files: #{total_files}"
      results.each do |r|
        puts "  - #{r.language}: found #{r.found_count}, missing #{r.missing_count}"
        if r.missing_count > 0
          puts "    Missing files:"
          r.missing_files.each { |f| puts "      - #{f}" }
        end
      end
      overall_missing = results.sum(&.missing_count)
      if overall_missing == 0
        puts "  🎉 All documentation files have translations for all languages!"
      else
        puts "  📝 Total missing translations across all languages: #{overall_missing}"
      end
    end
  end

  private def find_index_files(base_path : String) : Array(String)
    files = [] of String
    unless Dir.exists?(base_path)
      puts "Warning: Documentation directory '#{base_path}' does not exist." unless format == "json"
      return files
    end

    Dir.glob("#{base_path}/**/index.md").each { |f| files << f }
    Dir.glob("#{base_path}/**/_index.md").each { |f| files << f }

    files.sort!
    files
  end

  private def translated_file_path(original_path : String, lang : String) : String
    # Convert index.md to index.{lang}.md
    # Convert _index.md to _index.{lang}.md
    if original_path.ends_with?("index.md")
      original_path.sub(/index\.md$/, "index.#{lang}.md")
    elsif original_path.ends_with?("_index.md")
      original_path.sub(/_index\.md$/, "_index.#{lang}.md")
    else
      # Fallback for other *.md files if needed in the future
      original_path.sub(/\.md$/, ".#{lang}.md")
    end
  end
end

# ---------------------------
# CLI parsing and entry point
# ---------------------------

def parse_languages(str : String) : Array(String)
  str.split(/[,\s]+/).map(&.strip).reject(&.empty?).uniq!
end

base_path = "docs/content"
languages = [] of String
quiet = false
format = "text"
fail_on_missing = true
show_help = false

# Environment variable as default (overridden by CLI flags if provided)
if env_langs = ENV["NOIR_I18N_LANGS"]?
  languages = parse_languages(env_langs)
end

parser = OptionParser.new do |p|
  p.banner = "Usage: crystal run scripts/check_i18n_docs.cr -- [options]"

  p.on("-b PATH", "--base PATH", "Base documentation path (default: #{base_path})") do |path|
    base_path = path
  end

  p.on("-l LIST", "--langs LIST", "Comma/space-separated list of languages. Can be used multiple times.") do |list|
    languages.concat(parse_languages(list))
  end

  p.on("--format FORMAT", "Output format: text or json (default: #{format})") do |fmt|
    fmt_down = fmt.downcase
    unless {"text", "json"}.includes?(fmt_down)
      raise OptionParser::InvalidOption.new("Invalid format '#{fmt}'. Use 'text' or 'json'.")
    end
    format = fmt_down
  end

  p.on("-q", "--quiet", "Quiet mode (suppress per-file logs)") do
    quiet = true
  end

  p.on("--no-fail", "Do not fail (exit 1) when missing translations are found") do
    fail_on_missing = false
  end

  p.on("-h", "--help", "Show help") do
    show_help = true
  end
end

begin
  parser.parse
rescue ex : OptionParser::Exception
  STDERR.puts ex.message
  STDERR.puts
  STDERR.puts parser
  exit 2
end

if show_help
  puts parser
  puts
  puts "Environment:"
  puts "  NOIR_I18N_LANGS: Comma/space-separated languages (e.g., 'ko,ja,zh')."
  puts
  puts "Examples:"
  puts "  crystal run scripts/check_i18n_docs.cr -- -l ko,ja"
  puts "  crystal run scripts/check_i18n_docs.cr -- -l ko -l ja -b docs/content"
  puts "  NOIR_I18N_LANGS=ko,ja crystal run scripts/check_i18n_docs.cr"
  puts "  just docs-i18n-check"
  exit 0
end

# Default to Korean if nothing provided via env or CLI (backward compatible)
languages = ["ko"] if languages.empty?
languages.uniq!

checker = I18nDocsChecker.new(base_path, languages, quiet, format, fail_on_missing)
exit_code = checker.run
exit(exit_code)
