require "colorize"
require "json"
require "yaml"
require "../common"
require "../catalog"
require "../../techs/techs"
require "../../tagger/tagger"
require "../../output_builder/formats"

# `noir list <techs|taggers|formats>`
#
# Static built-in catalogs. These will never grow `update`-style verbs,
# so they live under a shared `list` namespace rather than as their own
# subcommand modules.
module Noir::CLI::ListCommand
  SUBJECTS         = Noir::CLI::Catalog::LIST_SUBJECTS
  AI_CONTEXT_KINDS = %w[guards sinks validators signals]

  # Output formats `list` itself understands. `text` is the human-readable
  # default; `json`/`yaml` re-serialize the same catalogs for scripting.
  LIST_FORMATS = %w[text json yaml]

  # Parsed argv. Extracted from `run` so the parser stays unit-testable
  # without going through the `exit`/`die` side effects. `errors` collects
  # unrecognized flags / stray positionals so `run` can reject them instead
  # of silently ignoring anything after the subject.
  record Parsed,
    subject : String?,
    format : String,
    help : Bool,
    errors : Array(String),
    rule_paths : Array(String) = [] of String

  def self.parse_argv(argv : Array(String)) : Parsed
    subject = nil
    format = "text"
    help = false
    errors = [] of String
    rule_paths = [] of String

    i = 0
    while i < argv.size
      arg = argv[i]
      case arg
      when "-h", "--help"
        help = true
      when "-f", "--format"
        value = argv[i + 1]?
        if value.nil?
          errors << "#{arg} requires a value (one of: #{LIST_FORMATS.join(", ")})"
        else
          format = value
          i += 1
        end
      when .starts_with?("-f=")
        format = arg[3..]
      when .starts_with?("--format=")
        format = arg[9..]
      when "--tagger-rules"
        if value = argv[i + 1]?
          rule_paths << value
          i += 1
        else
          errors << "--tagger-rules requires a path"
        end
      when .starts_with?("--tagger-rules=")
        rule_paths << arg["--tagger-rules=".size..]
      when .starts_with?("-")
        errors << "unknown option: #{arg}"
      else
        if subject.nil?
          subject = arg
        else
          errors << "unexpected argument: #{arg}"
        end
      end
      i += 1
    end

    if !rule_paths.empty? && subject && subject != "taggers"
      errors << "--tagger-rules only applies to `noir list taggers`"
    end

    Parsed.new(subject: subject, format: format, help: help, errors: errors, rule_paths: rule_paths)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help
      print_help
      exit
    end

    unless parsed.errors.empty?
      Noir::CLI.die("noir list: #{parsed.errors.join("; ")}")
    end

    if parsed.subject.nil?
      print_help
      exit
    end

    unless LIST_FORMATS.includes?(parsed.format)
      Noir::CLI.die("noir list: unknown format \"#{parsed.format}\". Valid: #{LIST_FORMATS.join(", ")}.")
    end

    case parsed.subject
    when "techs" then print_techs(parsed.format)
    when "taggers"
      rules = begin
        NoirTagRules.load_paths(parsed.rule_paths, NoirTaggers::ENTRIES.map(&.key).to_set)
      rescue ex : NoirTagRules::RuleError
        Noir::CLI.die(ex.message || "invalid tag rule")
      end
      print_taggers(parsed.format, custom_rules: rules)
    when "formats" then print_formats(parsed.format)
    else
      Noir::CLI.die("Unknown list subject: #{parsed.subject}. Valid: #{SUBJECTS.join(", ")}.")
    end
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir list <subject> [-f/--format text|json|yaml]

      #{green.call("SUBJECTS:")}
        #{cyan.call("techs")}                  Supported technologies and analyzer details
        #{cyan.call("taggers")}                Built-in and framework-specific taggers
        #{cyan.call("formats")}                Supported output formats

      #{green.call("OPTIONS:")}
        -f, --format <fmt>     Output as text (default), json, or yaml
        --tagger-rules <path>  Also list custom tag rules from a file or directory
                               (taggers only; repeatable), and check their examples

      #{green.call("LEGACY ALIASES")} (still work in v1.x):
        --list-techs           → noir list techs
        --list-taggers         → noir list taggers
      HELP
  end

  def self.print_techs(format : String = "text", io : IO = STDOUT)
    case format
    when "json" then io.puts techs_document.to_json
    when "yaml" then io.puts techs_document.to_yaml
    else             print_techs_text(io)
    end
  end

  def self.print_taggers(format : String = "text", io : IO = STDOUT, custom_rules : Array(NoirTagRules::Rule) = [] of NoirTagRules::Rule)
    case format
    when "json" then io.puts taggers_document(custom_rules).to_json
    when "yaml" then io.puts taggers_document(custom_rules).to_yaml
    else             print_taggers_text(io, custom_rules)
    end
  end

  def self.print_formats(format : String = "text", io : IO = STDOUT)
    case format
    when "json" then io.puts({"formats" => Noir::OutputFormats::NAMES}.to_json)
    when "yaml" then io.puts({"formats" => Noir::OutputFormats::NAMES}.to_yaml)
    else             print_formats_text(io)
    end
  end

  private def self.print_techs_text(io : IO)
    io.puts "Available technologies:"
    techs_document.as_h.each do |tech, info|
      io.puts " #{tech.colorize(:green)}"
      print_tech_fields(info, io, 3)
    end
  end

  # Rendered from `techs_document`, so the text view nests exactly like the
  # JSON/YAML ones instead of printing a nested Hash or Array via `inspect`.
  private def self.print_tech_fields(node : JSON::Any, io : IO, indent : Int32)
    node.as_h.each do |key, value|
      label = "#{" " * indent}#{key.colorize(indent == 3 ? :blue : :cyan)}:"
      if value.as_h?
        io.puts label
        print_tech_fields(value, io, indent + 2)
      elsif list = value.as_a?
        io.puts "#{label} #{list.join(", ")}"
      else
        io.puts "#{label} #{value}"
      end
    end
  end

  private def self.print_taggers_text(io : IO, custom_rules : Array(NoirTagRules::Rule))
    io.puts "Available taggers:"
    print_tagger_entries(NoirTaggers::PLAIN_ENTRIES, io)
    io.puts "\nFramework-specific taggers:"
    print_tagger_entries(NoirTaggers::FRAMEWORK_ENTRIES, io)
    return if custom_rules.empty?

    # This doubles as the way to check a rule file before a scan: the
    # examples are run here, where nothing else would run them.
    io.puts "\nCustom tag rules (--tagger-rules):"
    custom_rules.each do |rule|
      io.puts " #{rule.key.colorize(:green)}"
      io.puts "   #{"name".colorize(:blue)}: #{rule.name}"
      io.puts "   #{"desc".colorize(:blue)}: #{rule.summary}"
      io.puts "   #{"file".colorize(:blue)}: #{rule.source}"
      failures = NoirTagRules.example_failures(rule)
      if failures.empty?
        io.puts "   #{"examples".colorize(:blue)}: #{rule.match_examples.size + rule.no_match_examples.size} ok"
      else
        failures.each { |failure| io.puts "   #{"examples".colorize(:blue)}: #{failure.colorize(:yellow)}" }
      end
    end
  end

  private def self.print_tagger_entries(entries : Array(NoirTaggers::Entry), io : IO)
    entries.each do |entry|
      io.puts " #{entry.key.colorize(:green)}"
      io.puts "   #{"name".colorize(:blue)}: #{entry.name}"
      io.puts "   #{"desc".colorize(:blue)}: #{entry.desc}"
    end
  end

  # The one-line description beside each name is the same string `noir scan
  # -h` prints, because both read the annotation on the builder class.
  private def self.print_formats_text(io : IO)
    io.puts "Available output formats:"
    width = Noir::OutputFormats::ENTRIES.max_of(&.name.size)
    Noir::OutputFormats::ENTRIES.each do |entry|
      io.puts " #{entry.name.ljust(width).colorize(:green)}  #{entry.description}"
    end
  end

  # Structured techs catalog: the raw `NoirTechs.techs` metadata augmented with
  # the synthesized `callee` / `ai_context` support flags, so JSON/YAML output
  # carries the exact same information the text view prints under `supported:`.
  private def self.techs_document : JSON::Any
    doc = JSON.parse(NoirTechs.techs.to_json)
    doc.as_h.each do |tech, info|
      # Only declarations carry `:view`; everything else is code.
      info.as_h["view"] = JSON::Any.new(NoirTechs.view(tech))
      next unless supported = info.as_h["supported"]?
      target = supported.as_h
      target["callee"] = JSON::Any.new(NoirTechs.context_supported?(tech, "callee"))
      ai_context = {} of String => JSON::Any
      AI_CONTEXT_KINDS.each do |feature|
        ai_context[feature] = JSON::Any.new(NoirTechs.context_supported?(tech, feature))
      end
      target["ai_context"] = JSON::Any.new(ai_context)
    end
    doc
  end

  # Structured taggers catalog. The class that runs each tagger is an
  # internal detail and is not part of the document — the registry `Entry`
  # carries only what both views print.
  # `custom_taggers` appears only when `--tagger-rules` was given, so the
  # default document is unchanged.
  private def self.taggers_document(custom_rules : Array(NoirTagRules::Rule))
    doc = {
      "taggers"           => serialize_taggers(NoirTaggers::PLAIN_ENTRIES),
      "framework_taggers" => serialize_taggers(NoirTaggers::FRAMEWORK_ENTRIES),
    }
    return doc if custom_rules.empty?

    doc.merge({"custom_taggers" => custom_rules.map do |rule|
      {"id" => rule.key, "name" => rule.name, "desc" => rule.summary, "file" => rule.source,
       "example_failures" => NoirTagRules.example_failures(rule)}
    end})
  end

  private def self.serialize_taggers(source : Array(NoirTaggers::Entry)) : Array(Hash(String, String))
    source.map do |entry|
      {"id" => entry.key, "name" => entry.name, "desc" => entry.desc}
    end
  end
end
