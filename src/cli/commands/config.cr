require "colorize"
require "process"
require "../common"
require "../../config_initializer"
require "../../utils/home"

# `noir config <show|edit|init|path>`
#
# Managed resource: the user-level YAML configuration file.
module Noir::CLI::ConfigCommand
  ACTIONS = %w[show edit init path]

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
    when "edit" then edit
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
        #{cyan.call("edit")}                   Open the config file in $VISUAL / $EDITOR
        #{cyan.call("init")}                   Create the default config file (idempotent)
        #{cyan.call("path")}                   Print the resolved config file path

      The config directory is controlled by NOIR_HOME (defaults to
      $HOME/.config/noir on Unix and %APPDATA%\\noir on Windows).

      `edit` resolves the editor in the order $VISUAL, $EDITOR, then a
      platform default (vi on Unix, notepad on Windows). The config
      file is created first if it does not yet exist.
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

  def self.edit
    # Ensure the file exists before launching the editor so users always
    # land on something well-formed rather than a brand-new empty buffer.
    unless File.exists?(config_path)
      ConfigInitializer.new.setup
      if File.exists?(config_path)
        STDERR.puts "Created default config at #{config_path}"
      else
        Noir::CLI.die("Failed to create config file at #{config_path}.")
      end
    end

    editor = pick_editor
    command = "#{editor} #{Process.quote(config_path)}"
    status = Process.run(
      command,
      shell: true,
      input: Process::Redirect::Inherit,
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit,
    )

    unless status.success?
      Noir::CLI.die("Editor '#{editor}' exited with status #{status.exit_code}.")
    end
  end

  def self.config_path : String
    File.expand_path(File.join(get_home, "config.yaml"))
  end

  # Resolution order: $VISUAL, $EDITOR, then a platform default.
  # Empty/whitespace values are treated as unset so a stray empty
  # `EDITOR=` doesn't trap `edit` into running an empty command.
  # Public for unit-test reach.
  def self.pick_editor : String
    visual = ENV["VISUAL"]?
    return visual unless visual.nil? || visual.empty?

    editor = ENV["EDITOR"]?
    return editor unless editor.nil? || editor.empty?

    default_editor
  end

  def self.default_editor : String
    {% if flag?(:windows) %}
      "notepad"
    {% else %}
      "vi"
    {% end %}
  end
end
