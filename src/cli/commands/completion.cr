require "../common"
require "../../completions"

# `noir completion <zsh|bash|fish|elvish>`
#
# Replaces v0 `--generate-completion SHELL`.
module Noir::CLI::CompletionCommand
  SHELLS = %w[zsh bash fish elvish]

  # Parsed argv. Extracted from `run` so the parser stays unit-testable
  # without going through the `exit`/`die` side effects.
  record Parsed, shell : String?, help : Bool

  def self.parse_argv(argv : Array(String)) : Parsed
    shell = nil
    help = false
    argv.each do |a|
      case a
      when "-h", "--help"
        help = true
      else
        shell ||= a
      end
    end
    Parsed.new(shell: shell, help: help)
  end

  def self.run(argv : Array(String))
    parsed = parse_argv(argv)

    if parsed.help || parsed.shell.nil?
      print_help
      exit
    end

    case parsed.shell
    when "zsh"    then puts generate_zsh_completion_script
    when "bash"   then puts generate_bash_completion_script
    when "fish"   then puts generate_fish_completion_script
    when "elvish" then puts generate_elvish_completion_script
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

      Pipe the output to your shell's completion path, e.g.:
        noir completion zsh    > "${fpath[1]}/_noir"
        noir completion bash   > /etc/bash_completion.d/noir
        noir completion fish   > ~/.config/fish/completions/noir.fish
        noir completion elvish > ~/.config/elvish/lib/noir.elv
                                # then `use noir` from ~/.config/elvish/rc.elv
      HELP
  end
end
