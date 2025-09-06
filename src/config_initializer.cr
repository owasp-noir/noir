require "file"
require "yaml"
require "./utils/home.cr"

class ConfigInitializer
  @config_dir : String
  @config_file : String
  @default_config : Hash(String, YAML::Any) = {"key" => YAML::Any.new("default_value")} # Replace with your default config

  def initialize
    # Define the config directory and file based on ENV variables
    @config_dir = get_home

    @config_file = File.join(@config_dir, "config.yaml")

    # Expand the path (in case of '~')
    @config_dir = File.expand_path(@config_dir)
    @config_file = File.expand_path(@config_file)
  end

  def setup
    # Create the directory if it doesn't exist
    Dir.mkdir(@config_dir) unless Dir.exists?(@config_dir)
    Dir.mkdir("#{@config_dir}/passive_rules") unless Dir.exists?("#{@config_dir}/passive_rules")

    # Create the config file if it doesn't exist
    File.write(@config_file, generate_config_file) unless File.exists?(@config_file)
  rescue
  end

  def read_config
    # Ensure the config file is set up
    setup

    # Read the config file, or use the default config if reading fails
    begin
      parsed_yaml = YAML.parse(File.read(@config_file)).as_h
      symbolized_hash = parsed_yaml.transform_keys(&.to_s)

      # Transform specific keys from "yes"/"no" to true/false for old version noir config
      ["color", "debug", "include_path", "nolog", "send_req", "all_taggers"].each do |key|
        if symbolized_hash[key] == "yes"
          symbolized_hash[key] = YAML::Any.new(true)
        elsif symbolized_hash[key] == "no"
          symbolized_hash[key] = YAML::Any.new(false)
        end
      end

      # Transform specific keys for array and string config values
      [
        "send_with_headers", "use_filters", "use_matchers",
        "set_pvalue", "set_pvalue_header", "set_pvalue_cookie",
        "set_pvalue_query", "set_pvalue_form", "set_pvalue_json", "set_pvalue_path",
      ].each do |key|
        if symbolized_hash[key].to_s == ""
          # If the value is an empty string, initialize it as an empty array of YAML::Any
          symbolized_hash[key] = YAML::Any.new([] of YAML::Any)
        else
          begin
            # If the value is already an array, ensure it is treated as an array of YAML::Any
            symbolized_hash[key].as_a
          rescue
            # If the value is a string, wrap it in an array of YAML::Any
            symbolized_hash[key] = YAML::Any.new([YAML::Any.new(symbolized_hash[key].to_s)])
          end
        end
      end

      final_options = default_options.merge(symbolized_hash) { |_, _, new_val| new_val }
      final_options
    rescue e : Exception
      default_options
    end
  end

  def default_options
    noir_options = {
      "base"                         => YAML::Any.new(""),
      "color"                        => YAML::Any.new(true),
      "config_file"                  => YAML::Any.new(""),
      "concurrency"                  => YAML::Any.new("50"),
      "debug"                        => YAML::Any.new(false),
      "verbose"                      => YAML::Any.new(false),
      "exclude_codes"                => YAML::Any.new(""),
      "exclude_techs"                => YAML::Any.new(""),
      "format"                       => YAML::Any.new("plain"),
      "include_path"                 => YAML::Any.new(false),
      "nolog"                        => YAML::Any.new(false),
      "output"                       => YAML::Any.new(""),
      "send_es"                      => YAML::Any.new(""),
      "send_proxy"                   => YAML::Any.new(""),
      "send_req"                     => YAML::Any.new(false),
      "send_with_headers"            => YAML::Any.new([] of YAML::Any),
      "set_pvalue"                   => YAML::Any.new([] of YAML::Any),
      "set_pvalue_header"            => YAML::Any.new([] of YAML::Any),
      "set_pvalue_cookie"            => YAML::Any.new([] of YAML::Any),
      "set_pvalue_query"             => YAML::Any.new([] of YAML::Any),
      "set_pvalue_form"              => YAML::Any.new([] of YAML::Any),
      "set_pvalue_json"              => YAML::Any.new([] of YAML::Any),
      "set_pvalue_path"              => YAML::Any.new([] of YAML::Any),
      "status_codes"                 => YAML::Any.new(false),
      "techs"                        => YAML::Any.new(""),
      "url"                          => YAML::Any.new(""),
      "use_filters"                  => YAML::Any.new([] of YAML::Any),
      "use_matchers"                 => YAML::Any.new([] of YAML::Any),
      "all_taggers"                  => YAML::Any.new(false),
      "use_taggers"                  => YAML::Any.new(""),
      "diff"                         => YAML::Any.new(""),
      "passive_scan"                 => YAML::Any.new(false),
      "passive_scan_path"            => YAML::Any.new([] of YAML::Any),
      "passive_scan_severity"        => YAML::Any.new("high"),
      "passive_scan_auto_update"     => YAML::Any.new(false),
      "passive_scan_no_update_check" => YAML::Any.new(false),
      "ollama"                       => YAML::Any.new(""),
      "ollama_model"                 => YAML::Any.new(""),
      "ai_provider"                  => YAML::Any.new(""),
      "ai_model"                     => YAML::Any.new(""),
      "ai_key"                       => YAML::Any.new(""),
      "cache_disable"                => YAML::Any.new(false),
      "cache_clear"                  => YAML::Any.new(false),
      "analyze_feign"                => YAML::Any.new(false),
    }

    noir_options
  end

  def generate_config_file
    options = default_options
    content = <<-CONTENT
    ---
    # Noir configuration file
    # This file is used to store the configuration options for Noir.
    # You can edit this file to change the configuration options.

    # Config values are defaults; CLI options take precedence.
    # **************************************************************

    # Base directory for the application
    base: "#{options["base"]}"

    # Whether to use color in the output
    color: #{options["color"]}

    # The configuration file to use
    config_file: "#{options["config_file"]}"

    # The number of concurrent operations to perform
    concurrency: "#{options["concurrency"]}"

    # Whether to enable debug mode
    debug: #{options["debug"]}

    # Whether to enable verbose mode
    verbose: #{options["verbose"]}

    # The status codes to exclude
    exclude_codes: "#{options["exclude_codes"]}"

    # Technologies to exclude
    exclude_techs: "#{options["exclude_techs"]}"

    # The format to use for the output
    format: "#{options["format"]}"

    # Whether to include the path in the output
    include_path: #{options["include_path"]}

    # Whether to disable logging
    nolog: #{options["nolog"]}

    # The output file to write to
    output: "#{options["output"]}"

    # The Elasticsearch server to send data to
    # e.g http://localhost:9200
    send_es: "#{options["send_es"]}"

    # The proxy server to use
    # e.g http://localhost:8080
    send_proxy: "#{options["send_proxy"]}"

    # Whether to send a request
    send_req: #{options["send_req"]}

    # Whether to send headers with the request (Array of strings)
    # e.g "Authorization: Bearer token"
    send_with_headers:

    # The value to set for pvalue (Array of strings)
    set_pvalue:
    set_pvalue_header:
    set_pvalue_cookie:
    set_pvalue_query:
    set_pvalue_form:
    set_pvalue_json:
    set_pvalue_path:

    # The status codes to use
    status_codes: #{options["status_codes"]}

    # The technologies to use
    techs: "#{options["techs"]}"

    # The URL to use
    url: "#{options["url"]}"

    # Whether to use filters (Array of strings)
    use_filters:

    # Whether to use matchers (Array of strings)
    use_matchers:

    # Whether to use all taggers
    all_taggers: #{options["all_taggers"]}

    # The taggers to use
    # e.g "tagger1,tagger2"
    # To see the list of all taggers, please use the noir command with --list-taggers
    use_taggers: "#{options["use_taggers"]}"

    # The diff file to use
    diff: "#{options["diff"]}"

    # The passive rules to use
    # e.g /path/to/rules
    passive_scan: false
    passive_scan_path: []

    # Minimum severity level for passive scan (critical, high, medium, low)
    # Default: high (detects high and critical severity issues)
    passive_scan_severity: "high"

    # Automatically update passive rules from repository at startup
    passive_scan_auto_update: false

    # Skip checking for passive rules updates at startup
    passive_scan_no_update_check: false

    # The AI server URL
    ai_provider: "#{options["ai_provider"]}"

    # The AI model to use
    ai_model: "#{options["ai_model"]}"

    # The API key for the AI server
    ai_key: "#{options["ai_key"]}"

    # CACHE:
    # Disable LLM disk cache for this run
    cache_disable: #{options["cache_disable"]}

    # Clear LLM cache directory before run
    cache_clear: #{options["cache_clear"]}

    CONTENT

    content
  end
end
