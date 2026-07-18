require "colorize"
require "json"
require "yaml"
require "../common"
require "../../techs/techs"
require "../../tagger/tagger"
require "../../cli_validation"

# `noir list <techs|taggers|formats>`
#
# Static built-in catalogs. These will never grow `update`-style verbs,
# so they live under a shared `list` namespace rather than as their own
# subcommand modules.
module Noir::CLI::ListCommand
  SUBJECTS         = %w[techs taggers formats]
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
    errors : Array(String)

  def self.parse_argv(argv : Array(String)) : Parsed
    subject = nil
    format = "text"
    help = false
    errors = [] of String

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

    Parsed.new(subject: subject, format: format, help: help, errors: errors)
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
    when "techs"   then print_techs(parsed.format)
    when "taggers" then print_taggers(parsed.format)
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

  def self.print_taggers(format : String = "text", io : IO = STDOUT)
    case format
    when "json" then io.puts taggers_document.to_json
    when "yaml" then io.puts taggers_document.to_yaml
    else             print_taggers_text(io)
    end
  end

  def self.print_formats(format : String = "text", io : IO = STDOUT)
    case format
    when "json" then io.puts({"formats" => Noir::CliValidation::VALID_OUTPUT_FORMATS}.to_json)
    when "yaml" then io.puts({"formats" => Noir::CliValidation::VALID_OUTPUT_FORMATS}.to_yaml)
    else             print_formats_text(io)
    end
  end

  private def self.print_techs_text(io : IO)
    io.puts "Available technologies:"
    NoirTechs.techs.each do |tech, info|
      io.puts " #{tech.to_s.colorize(:green)}"
      info.each do |k, v|
        if v.is_a?(Hash)
          io.puts "   #{k.to_s.colorize(:blue)}:"
          v.each { |sk, sv| io.puts "     #{sk.to_s.colorize(:cyan)}: #{sv}" }
          print_context_support(tech.to_s, io) if k.to_s == "supported"
        else
          io.puts "   #{k.to_s.colorize(:blue)}: #{v}"
        end
      end
    end
  end

  private def self.print_taggers_text(io : IO)
    io.puts "Available taggers:"
    NoirTaggers.taggers.each do |tagger, info|
      io.puts " #{tagger.to_s.colorize(:green)}"
      info.each { |k, v| io.puts "   #{k.to_s.colorize(:blue)}: #{v}" unless k == :runner }
    end
    io.puts "\nFramework-specific taggers:"
    NoirTaggers.framework_taggers.each do |tagger, info|
      io.puts " #{tagger.to_s.colorize(:green)}"
      info.each { |k, v| io.puts "   #{k.to_s.colorize(:blue)}: #{v}" unless k == :runner }
    end
  end

  private def self.print_formats_text(io : IO)
    io.puts "Available output formats:"
    Noir::CliValidation::VALID_OUTPUT_FORMATS.each do |fmt|
      io.puts " #{fmt.colorize(:green)}"
    end
  end

  # Structured techs catalog: the raw `NoirTechs.techs` metadata augmented with
  # the synthesized `callee` / `ai_context` support flags, so JSON/YAML output
  # carries the exact same information the text view prints under `supported:`.
  private def self.techs_document : JSON::Any
    doc = JSON.parse(NoirTechs.techs.to_json)
    doc.as_h.each do |tech, info|
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

  # Structured taggers catalog. The `:runner` class reference isn't
  # serializable (and is an internal detail), so it's dropped — matching the
  # text view, which also hides it.
  private def self.taggers_document
    {
      "taggers"           => serialize_taggers(NoirTaggers.taggers),
      "framework_taggers" => serialize_taggers(NoirTaggers.framework_taggers),
    }
  end

  private def self.serialize_taggers(source) : Array(Hash(String, String))
    entries = [] of Hash(String, String)
    source.each do |name, info|
      entry = {"id" => name.to_s}
      info.each do |k, v|
        next if k == :runner
        entry[k.to_s] = v.to_s
      end
      entries << entry
    end
    entries
  end

  private def self.print_context_support(tech : String, io : IO)
    io.puts "     #{"callee".colorize(:cyan)}: #{NoirTechs.context_supported?(tech, "callee")}"
    io.puts "     #{"ai_context".colorize(:cyan)}:"
    AI_CONTEXT_KINDS.each do |feature|
      io.puts "       #{feature.colorize(:cyan)}: #{NoirTechs.context_supported?(tech, feature)}"
    end
  end
end
