require "file"
require "yaml"

class ConfigInitializer
  @config_dir : String
  @config_file : String
  @default_config : Hash(String, String) = {"key" => "default_value"} # Replace with your default config

  def initialize
    # Define the config directory and file based on the OS
    {% if flag?(:windows) %}
      @config_dir = "#{ENV["APPDATA"]}\\noir"
    {% else %}
      @config_dir = "#{ENV["HOME"]}/.config/noir"
    {% end %}
    @config_file = File.join(@config_dir, "config.yaml")

    # Expand the path (in case of '~')
    @config_dir = File.expand_path(@config_dir)
    @config_file = File.expand_path(@config_file)
  end

  def setup
    # Create the directory if it doesn't exist
    Dir.mkdir(@config_dir) unless Dir.exists?(@config_dir)

    # Get the default options
    options = default_options

    # Convert the options to a YAML string
    yaml_string = options.to_yaml

    # Create the config file if it doesn't exist
    File.write(@config_file, yaml_string) unless File.exists?(@config_file)
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
end
