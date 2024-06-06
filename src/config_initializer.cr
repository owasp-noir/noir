require "file"
require "yaml"

class ConfigInitializer
  @config_dir : String
  @config_file : String
  @default_config : Hash(String, String) = {"key" => "default_value"} # Replace with your default config

  def initialize
    # Define the config directory and file based on ENV variables
    if ENV.has_key? "NOIR_HOME"
      @config_dir = ENV["NOIR_HOME"]
    else
      # Define the config directory and file based on the OS
      {% if flag?(:windows) %}
        @config_dir = "#{ENV["APPDATA"]}\\noir"
      {% else %}
        @config_dir = "#{ENV["HOME"]}/.config/noir"
      {% end %}
    end

    @config_file = File.join(@config_dir, "config.yaml")

    # Expand the path (in case of '~')
    @config_dir = File.expand_path(@config_dir)
    @config_file = File.expand_path(@config_file)
  end

  def setup
    # Create the directory if it doesn't exist
    Dir.mkdir(@config_dir) unless Dir.exists?(@config_dir)

    # Create the config file if it doesn't exist
    File.write(@config_file, generate_config_file) unless File.exists?(@config_file)
  rescue e : Exception
    puts "Failed to create config directory or file: #{e.message}"
    puts "Using default config."
  end

  def read_config
    # Ensure the config file is set up
    setup

    # Read the config file, or use the default config if reading fails
    begin
      parsed_yaml = YAML.parse(File.read(@config_file)).as_h
      symbolized_hash = parsed_yaml.transform_keys(&.to_s)
      stringlized_hash = symbolized_hash.transform_values(&.to_s)

      stringlized_hash
    rescue e : Exception
      puts "Failed to read config file: #{e.message}"
      puts "Using default config."

      default_options
    end
  end

  def default_options
    noir_options = {
      "base"              => "",
      "color"             => "yes",
      "config_file"       => "",
      "concurrency"       => "100",
      "debug"             => "no",
      "exclude_techs"     => "",
      "format"            => "plain",
      "include_path"      => "no",
      "nolog"             => "no",
      "output"            => "",
      "send_es"           => "",
      "send_proxy"        => "",
      "send_req"          => "no",
      "send_with_headers" => "",
      "set_pvalue"        => "",
      "techs"             => "",
      "url"               => "",
      "use_filters"       => "",
      "use_matchers"      => "",
      "all_taggers"       => "no",
      "use_taggers"       => "",
      "diff"              => "",
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
    # **************************************************************

    # Base directory for the application
    base: "#{options["base"]}"

    # Whether to use color in the output
    color: "#{options["color"]}"

    # The configuration file to use
    config_file: "#{options["config_file"]}"

    # The number of concurrent operations to perform
    concurrency: "#{options["concurrency"]}"

    # Whether to enable debug mode
    debug: "#{options["debug"]}"

    # Technologies to exclude
    exclude_techs: "#{options["exclude_techs"]}"

    # The format to use for the output
    format: "#{options["format"]}"

    # Whether to include the path in the output
    include_path: "#{options["include_path"]}"

    # Whether to disable logging
    nolog: "#{options["nolog"]}"

    # The output file to write to
    output: "#{options["output"]}"

    # The Elasticsearch server to send data to
    send_es: "#{options["send_es"]}"

    # The proxy server to use
    send_proxy: "#{options["send_proxy"]}"

    # Whether to send a request
    send_req: "#{options["send_req"]}"

    # Whether to send headers with the request
    send_with_headers: "#{options["send_with_headers"]}"

    # The value to set for pvalue
    set_pvalue: "#{options["set_pvalue"]}"

    # The technologies to use
    techs: "#{options["techs"]}"

    # The URL to use
    url: "#{options["url"]}"

    # Whether to use filters
    use_filters: "#{options["use_filters"]}"

    # Whether to use matchers
    use_matchers: "#{options["use_matchers"]}"

    # Whether to use all taggers
    all_taggers: "#{options["all_taggers"]}"

    # The taggers to use
    use_taggers: "#{options["use_taggers"]}"

    # The diff file to use
    diff: "#{options["diff"]}"

    CONTENT

    content
  end
end
