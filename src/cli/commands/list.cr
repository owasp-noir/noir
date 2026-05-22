require "option_parser"
require "colorize"
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
  SUBJECTS = %w[techs taggers formats]

  def self.run(argv : Array(String))
    subject = nil
    rest = [] of String
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      else
        if subject.nil?
          subject = a
        else
          rest << a
        end
      end
    end

    if subject.nil?
      print_help
      exit
    end

    case subject
    when "techs"   then print_techs
    when "taggers" then print_taggers
    when "formats" then print_formats
    else
      Noir::CLI.die("Unknown list subject: #{subject}. Valid: #{SUBJECTS.join(", ")}.")
    end
  end

  def self.print_help
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    puts <<-HELP
      #{green.call("USAGE:")}
        noir list <subject>

      #{green.call("SUBJECTS:")}
        #{cyan.call("techs")}                  Supported technologies and analyzer details
        #{cyan.call("taggers")}                Built-in and framework-specific taggers
        #{cyan.call("formats")}                Supported output formats

      #{green.call("LEGACY ALIASES")} (still work in v1.x):
        --list-techs           → noir list techs
        --list-taggers         → noir list taggers
      HELP
  end

  def self.print_techs
    puts "Available technologies:"
    NoirTechs.techs.each do |tech, info|
      puts " #{tech.to_s.colorize(:green)}"
      info.each do |k, v|
        if v.is_a?(Hash)
          puts "   #{k.to_s.colorize(:blue)}:"
          v.each { |sk, sv| puts "     #{sk.to_s.colorize(:cyan)}: #{sv}" }
          print_context_support(tech.to_s) if k.to_s == "supported"
        else
          puts "   #{k.to_s.colorize(:blue)}: #{v}"
        end
      end
    end
  end

  def self.print_taggers
    puts "Available taggers:"
    NoirTaggers.taggers.each do |tagger, info|
      puts " #{tagger.to_s.colorize(:green)}"
      info.each { |k, v| puts "   #{k.to_s.colorize(:blue)}: #{v}" unless k == :runner }
    end
    puts "\nFramework-specific taggers:"
    NoirTaggers.framework_taggers.each do |tagger, info|
      puts " #{tagger.to_s.colorize(:green)}"
      info.each { |k, v| puts "   #{k.to_s.colorize(:blue)}: #{v}" unless k == :runner }
    end
  end

  def self.print_formats
    puts "Available output formats:"
    Noir::CliValidation::VALID_OUTPUT_FORMATS.each do |fmt|
      puts " #{fmt.colorize(:green)}"
    end
  end

  private def self.print_context_support(tech : String)
    puts "     #{"callee".colorize(:cyan)}: #{NoirTechs.context_supported?(tech, "callee")}"
    puts "     #{"ai_context".colorize(:cyan)}:"
    ["guards", "sinks", "validators", "signals"].each do |feature|
      puts "       #{feature.colorize(:cyan)}: #{NoirTechs.context_supported?(tech, feature)}"
    end
  end
end
