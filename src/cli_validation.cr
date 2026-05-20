require "colorize"
require "yaml"
require "./tagger/tagger"

module Noir::CliValidation
  class Error < Exception
  end

  VALID_OUTPUT_FORMATS = %w[
    plain
    yaml
    json
    jsonl
    toml
    markdown-table
    sarif
    html
    curl
    httpie
    powershell
    oas2
    oas3
    postman
    only-url
    only-param
    only-header
    only-cookie
    only-tag
    mermaid
  ]

  def self.validate!(options : Hash(String, YAML::Any))
    validate_base_paths!(options)
    validate_output_format!(options)
    validate_concurrency!(options)
    validate_output_path!(options)
    validate_tagger_names!(options)
  end

  def self.validate_base_paths!(options : Hash(String, YAML::Any))
    base_paths = options["base"].as_a.map(&.to_s)
    if base_paths.empty?
      raise Error.new("Base path is required.\nPlease use -b or --base-path to set base path.\nIf you need help, use -h or --help.")
    end

    base_paths.each do |base_path|
      unless File.exists?(base_path)
        raise Error.new("Base path does not exist: #{base_path}")
      end

      unless File.directory?(base_path)
        raise Error.new("Base path is not a directory: #{base_path}")
      end
    end
  end

  def self.validate_output_format!(options : Hash(String, YAML::Any))
    format = options["format"].to_s
    return if VALID_OUTPUT_FORMATS.includes?(format)

    raise Error.new("Invalid output format '#{format}'. Valid formats: #{VALID_OUTPUT_FORMATS.join(", ")}")
  end

  def self.validate_concurrency!(options : Hash(String, YAML::Any))
    raw_value = options["concurrency"].to_s
    value = raw_value.to_i?
    if value.nil? || value < 1
      raise Error.new("Invalid concurrency '#{raw_value}'. Concurrency must be an integer greater than or equal to 1.")
    end

    options["concurrency"] = YAML::Any.new(value)
  end

  def self.validate_output_path!(options : Hash(String, YAML::Any))
    output_path = options["output"].to_s
    return if output_path.empty?

    if File.exists?(output_path) && File.directory?(output_path)
      raise Error.new("Output path is a directory: #{output_path}")
    end

    output_dir = File.dirname(output_path)
    return if output_dir == "." || output_dir.empty?
    return if Dir.exists?(output_dir)

    raise Error.new("Output directory does not exist: #{output_dir}")
  end

  def self.validate_tagger_names!(options : Hash(String, YAML::Any))
    use_taggers = options["use_taggers"].to_s
    return if use_taggers.empty?

    unknown_taggers = NoirTaggers.unknown_tagger_names(use_taggers)
    return if unknown_taggers.empty?

    raise Error.new("Unknown tagger(s): #{unknown_taggers.join(", ")}. Use --list-taggers to see available taggers.")
  end

  def self.exit_with_error(message : String) : NoReturn
    lines = message.lines
    STDERR.puts "ERROR: #{lines.first}".colorize(:yellow)
    lines[1..]?.try do |rest|
      rest.each { |line| STDERR.puts line }
    end
    exit(1)
  end
end
