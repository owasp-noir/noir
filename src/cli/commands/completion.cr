require "../common"
require "../../completions"

# `noir completion <zsh|bash|fish>`
#
# Replaces v0 `--generate-completion SHELL`.
module Noir::CLI::CompletionCommand
  SHELLS = %w[zsh bash fish]

  def self.run(argv : Array(String))
    shell = nil
    argv.each do |a|
      case a
      when "-h", "--help"
        print_help
        exit
      else
        shell ||= a
      end
    end

    if shell.nil?
      print_help
      exit
    end

    case shell
    when "zsh"  then puts generate_zsh_completion_script
    when "bash" then puts generate_bash_completion_script
    when "fish" then puts generate_fish_completion_script
    else
      Noir::CLI.die("Unsupported shell: #{shell}. Valid: #{SHELLS.join(", ")}.")
    end
  end

  def self.print_help
    puts <<-HELP
      USAGE:
        noir completion <shell>

      SHELLS:
        zsh                  Generate Zsh completion script
        bash                 Generate Bash completion script
        fish                 Generate Fish completion script

      Pipe the output to your shell's completion path, e.g.:
        noir completion zsh  > "${fpath[1]}/_noir"
        noir completion bash > /etc/bash_completion.d/noir
      HELP
  end
end
