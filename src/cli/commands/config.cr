require "colorize"
require "../common"
require "../../config_initializer"
require "../../utils/home"

# `noir config <show|init|path>`
#
# Managed resource: the user-level YAML configuration file.
module Noir::CLI::ConfigCommand
  ACTIONS = %w[show init path]

  def self.run(argv : Array(String))
    action = nil
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      else
        action ||= a
      end
    end

    if action.nil?
      print_help
      exit
    end

    case action
    when "show" then show
    when "init" then init
    when "path" then puts config_path
    else
      Noir::CLI.die("Unknown config action: #{action}. Valid: #{ACTIONS.join(", ")}.")
    end
  end

  def self.print_help
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    puts <<-HELP
      #{green.call("USAGE:")}
        noir config <action>

      #{green.call("ACTIONS:")}
        #{cyan.call("show")}                   Print the contents of the active config file
        #{cyan.call("init")}                   Create the default config file (idempotent)
        #{cyan.call("path")}                   Print the resolved config file path

      The config directory is controlled by NOIR_HOME (defaults to
      $HOME/.config/noir on Unix and %APPDATA%\\noir on Windows).
      HELP
  end

  def self.show
    path = config_path
    unless File.exists?(path)
      Noir::CLI.die("Config file does not exist: #{path}\nRun `noir config init` to create it.")
    end
    puts File.read(path)
  end

  def self.init
    config_init = ConfigInitializer.new
    path = config_path
    if File.exists?(path)
      puts "Config file already exists at: #{path}"
      return
    end

    config_init.setup
    if File.exists?(path)
      puts "Created config file at: #{path}"
    else
      Noir::CLI.die("Failed to create config file at #{path}.")
    end
  end

  def self.config_path : String
    File.expand_path(File.join(get_home, "config.yaml"))
  end
end
