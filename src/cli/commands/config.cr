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
    override_path = nil
    i = 0
    while i < argv.size
      a = argv[i]
      case a
      when "-h", "--help"
        print_help
        exit
      when "--config-file"
        # Honor the global --config-file flag inside the subcommand so
        # `noir config show --config-file X` reads X, not the default path.
        override_path = argv[i + 1]?
        i += 1
      when .starts_with?("--config-file=")
        override_path = a.split("=", 2)[1]
      else
        action ||= a
      end
      i += 1
    end

    if action.nil?
      print_help
      exit
    end

    case action
    when "show" then show(override_path)
    when "edit" then edit(override_path)
    when "init"
      # `init` only ever creates the DEFAULT config file — it has no
      # override_path parameter (auto-scaffolding at a user-supplied
      # path would mask a typo). Passing --config-file here is a no-op,
      # so say so instead of silently ignoring it.
      if override_path && !override_path.empty?
        STDERR.puts "NOTE: `noir config init` always creates the default config file; --config-file #{override_path} is ignored.".colorize(:yellow)
      end
      init
    when "path" then puts config_path(override_path)
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

      #{green.call("OPTIONS:")}
        #{cyan.call("--config-file PATH")}     Operate on PATH instead of the default config file.
                               Applies to show, edit, and path; init always
                               creates the default file and ignores this flag.

      The config directory is controlled by NOIR_HOME (defaults to
      $HOME/.config/noir on Unix and %APPDATA%\\noir on Windows).

      `edit` resolves the editor in the order $VISUAL, $EDITOR, then a
      platform default (vi on Unix, notepad on Windows). The config
      file is created first if it does not yet exist.
      HELP
  end

  def self.show(override_path : String? = nil)
    path = config_path(override_path)

    if override_path && !override_path.empty?
      # A custom --config-file is validated the way the scan path does:
      # a missing file or a directory is a user error. Crucially, don't
      # print the `noir config init` hint here — init only ever creates
      # the DEFAULT config, so following that advice can't fix a custom
      # path. Reading a directory would also crash `File.read` with a
      # raw backtrace, so reject it explicitly.
      Noir::CLI.die("Config file does not exist: #{path}") unless File.exists?(path)
      Noir::CLI.die("--config-file is not a file: #{path}") if File.directory?(path)
    elsif !File.exists?(path)
      Noir::CLI.die("Config file does not exist: #{path}\nRun `noir config init` to create it.")
    end

    content = File.read(path)
    puts content
    warn_about_legacy_keys(content)
  end

  # Emit a stderr hint when v0 deliver/probe keys are present in the
  # config file. The keys keep working (the migration runs at scan
  # time), but a user running `noir config show` to verify their
  # settings would otherwise see the raw v0 names and wonder why the
  # v1 documentation doesn't match what's on disk.
  def self.warn_about_legacy_keys(content : String, io : IO = STDERR)
    legacy_keys = detect_legacy_keys(content)
    return if legacy_keys.empty?

    io.puts ""
    io.puts "NOTE: v0 keys detected in this config file. They still work — noir auto-migrates them at load time — but the canonical v1 names are:".colorize(:yellow)
    legacy_keys.each do |old_key, new_key|
      io.puts "  #{old_key}  ->  #{new_key}".colorize(:yellow)
    end
  end

  # Pure helper — given a config file's body, returns the v0 keys
  # present in it as `{old_key => v1_key}`. Pulled out so the
  # detection rule can be exercised without going through STDERR.
  def self.detect_legacy_keys(content : String) : Hash(String, String)
    ConfigInitializer::LEGACY_CONFIG_KEY_MAP.select do |old_key, _|
      content =~ /^\s*#{Regex.escape(old_key)}\s*:/m
    end
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

  def self.edit(override_path : String? = nil)
    path = config_path(override_path)

    # A custom --config-file pointing at a directory would otherwise be
    # handed straight to the editor (or crash on the create path). Reject
    # it up front, matching `show` and the scan-path validator.
    if override_path && !override_path.empty? && File.directory?(path)
      Noir::CLI.die("--config-file is not a file: #{path}")
    end

    # `edit` launches an interactive terminal editor. In a non-interactive
    # context (CI, piped stdin, background job) that editor would block
    # forever waiting for input that never arrives, hanging the pipeline.
    # Fail fast with a useful pointer instead.
    unless STDIN.tty?
      Noir::CLI.die("`noir config edit` needs an interactive terminal. Edit #{path} directly, or use `noir config show`.")
    end

    # Ensure the file exists before launching the editor so users always
    # land on something well-formed rather than a brand-new empty buffer. Only
    # the default path is auto-created (via ConfigInitializer); a custom
    # --config-file that doesn't exist is an error, not a place to scaffold.
    unless File.exists?(path)
      if override_path && !override_path.empty?
        Noir::CLI.die("Config file does not exist: #{path}")
      end
      ConfigInitializer.new.setup
      if File.exists?(path)
        STDERR.puts "Created default config at #{path}"
      else
        Noir::CLI.die("Failed to create config file at #{path}.")
      end
    end

    editor = pick_editor
    # Split the editor string into argv WITHOUT a shell so a poisoned
    # $EDITOR/$VISUAL can't inject commands: `EDITOR="rm -rf /; vi"` used to
    # run under `shell: true` and execute `rm -rf /`. Parsing to argv means
    # metacharacters (`;`, `|`, `$()`) are passed literally, never evaluated,
    # while still supporting editors carrying flags (e.g. `code --wait`).
    editor_argv = Process.parse_arguments(editor)
    if editor_argv.empty?
      Noir::CLI.die("No editor configured. Set $VISUAL or $EDITOR (or install vi).")
    end
    command = editor_argv.first
    args = editor_argv[1..] + [path]
    status = Process.run(
      command,
      args: args,
      input: Process::Redirect::Inherit,
      output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit,
    )

    unless status.success?
      Noir::CLI.die("Editor '#{editor}' exited with status #{status.exit_code}.")
    end
  end

  def self.config_path(override : String? = nil) : String
    return File.expand_path(override) if override && !override.empty?
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
