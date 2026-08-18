require "../common"
require "../catalog"
require "../../completions"

# `noir completion <zsh|bash|fish|elvish>`
#
# Replaces v0 `--generate-completion SHELL`.
module Noir::CLI::CompletionCommand
  SHELLS = Noir::CLI::Catalog::SHELLS

  # Parsed argv. Extracted from `run` so the parser stays unit-testable
  # without going through the `exit`/`die` side effects. `error` is
  # recorded rather than raised so `run` can turn it into a clean
  # `Noir::CLI.die` line.
  record Parsed, shell : String?, help : Bool, error : String?

  def self.parse_argv(argv : Array(String)) : Parsed
    shell = nil
    help = false
    error = nil
    rest = [] of String

    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      when "--no-color", "--no-spinner"
        # Global flags — the router consumes both before dispatching here.
        # Accepted (not rejected as unknown) so a direct `run` call and a
        # future router change both behave.
      else
        if a.starts_with?("-")
          # Silently ignoring an unknown flag meant `noir completion zsh
          # --oops` emitted a script and exited 0, hiding the typo.
          error ||= "Unknown option: #{a}. Run `noir completion --help`."
        elsif shell.nil?
          # Shell names are matched case-insensitively (`ZSH` == `zsh`).
          shell = a.downcase
        else
          rest << a
        end
      end
    end

    # `noir completion zsh bash` used to emit zsh only, exit 0, and leave
    # the user's bash completion silently unwritten. `cache` and `rules`
    # already reject surplus positionals; so does this now.
    if error.nil? && !rest.empty?
      plural = rest.size > 1 ? "s" : ""
      error = "Unexpected argument#{plural}: #{rest.join(", ")}. Usage: noir completion <shell>"
    end

    Parsed.new(shell: shell, help: help, error: error)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help
      print_help
      exit
    end

    if err = parsed.error
      Noir::CLI.die(err)
    end

    if parsed.shell.nil?
      print_help
      exit
    end

    case parsed.shell
    when "zsh"    then puts Noir::Completions::Zsh.script
    when "bash"   then puts Noir::Completions::Bash.script
    when "fish"   then puts Noir::Completions::Fish.script
    when "elvish" then puts Noir::Completions::Elvish.script
    else
      Noir::CLI.die("Unsupported shell: #{parsed.shell}. Valid: #{SHELLS.join(", ")}.")
    end
  end

  def self.print_help(io : IO = STDOUT)
    cyan = ->(s : String) { Noir::CLI.name(s) }
    green = ->(s : String) { Noir::CLI.section(s) }

    io.puts <<-HELP
      #{green.call("USAGE:")}
        noir completion <shell>

      #{green.call("SHELLS:")}
        #{cyan.call("zsh")}                    Generate Zsh completion script
        #{cyan.call("bash")}                   Generate Bash completion script
        #{cyan.call("fish")}                   Generate Fish completion script
        #{cyan.call("elvish")}                 Generate Elvish completion script

      Pipe the output to your shell's completion path — these create the
      target dir first so they work on a fresh macOS/Linux setup:
        noir completion zsh    > "${fpath[1]}/_noir"
        mkdir -p ~/.local/share/bash-completion/completions
        noir completion bash   > ~/.local/share/bash-completion/completions/noir
        mkdir -p ~/.config/fish/completions
        noir completion fish   > ~/.config/fish/completions/noir.fish
        mkdir -p ~/.config/elvish/lib
        noir completion elvish > ~/.config/elvish/lib/noir.elv
                                # then `use noir` from ~/.config/elvish/rc.elv
      HELP
  end
end
