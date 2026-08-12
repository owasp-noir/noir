require "../cli/catalog"
require "../cli/scan_flags"
require "./shell"

module Noir::Completions::Fish
  extend self

  alias Arg = Noir::CLI::ScanFlags::Arg

  # Guard so scan/global flags only complete under an explicit `noir scan
  # ...` or a bare `noir ...` (v0 compat) — never leaking into `noir cache`,
  # `noir config`, and the other subcommands.
  SCAN_GUARD = "-n __fish_noir_scan_context"

  def script : String
    <<-SCRIPT
      function __fish_noir_using_command
          set -l cmd (commandline -opc)
          if test (count $cmd) -ge 2
              if test "$cmd[2]" = $argv[1]
                  return 0
              end
          end
          return 1
      end

      function __fish_noir_needs_command
          set -l cmd (commandline -opc)
          if test (count $cmd) -eq 1
              return 0
          end
          return 1
      end

      # True when the current line is (or is becoming) a scan: an explicit
      # `noir scan ...`, or a bare `noir <flag> ...` v0 invocation, or an
      # empty `noir ` line before any subcommand is chosen.
      function __fish_noir_scan_context
          set -l cmd (commandline -opc)
          if test (count $cmd) -eq 1
              return 0
          end
          if test "$cmd[2]" = scan
              return 0
          end
          if string match -q -- '-*' "$cmd[2]"
              return 0
          end
          return 1
      end

      # Top-level subcommands
      #{command_completions}

      # Sub-actions per command
      #{action_completions}

      # Scan-time flags (also valid under bare `noir` for v0 compat)
      #{flag_completions}
      SCRIPT
  end

  private def command_completions : String
    width = Noir::CLI::Catalog::NAMES.max_of(&.size)
    Noir::CLI::Catalog::COMMANDS.map do |command|
      "complete -c noir -f -n '__fish_noir_needs_command' " \
      "-a #{command.name.ljust(width)} -d #{Noir::Completions.quote(command.summary)}"
    end.join("\n")
  end

  private def action_completions : String
    Noir::CLI::Catalog.completable.reject { |(_, values)| values.empty? }.map do |(name, values)|
      "complete -c noir -f -n '__fish_noir_using_command #{name}' -a '#{values.join(" ")}'"
    end.join("\n")
  end

  private def flag_completions : String
    # Both columns are padded so the `-l` names and the descriptions line up
    # whether or not a flag has short forms — the generated file is meant to
    # stay readable for anyone who opens the one their shell installed.
    short_width = Noir::CLI::ScanFlags::FLAGS.max_of { |flag| short_forms(flag).size }
    width = Noir::CLI::ScanFlags::FLAGS.max_of(&.long.lchop("--").size)

    Noir::CLI::ScanFlags::FLAGS.map do |flag|
      String.build do |line|
        line << "complete -c noir " << SCAN_GUARD << " "
        line << short_forms(flag).ljust(short_width)
        line << "-l " << flag.long.lchop("--").ljust(width)
        line << " -d " << Noir::Completions.quote(flag.description)
        # `-r` marks the flag as requiring a value; `-F` lets fish fall back
        # to filenames for the ones that take a path.
        line << " -r" if requires_value?(flag)
        line << " -F" if flag.arg.file?
        line << " -a '" << flag.choice_list << '\'' unless flag.choices.empty?
      end
    end.join("\n")
  end

  # `-s b -s V ` — fish spells short forms without the leading dash.
  private def short_forms(flag : Noir::CLI::ScanFlags::Flag) : String
    flag.shorts.map { |short| "-s #{short.lchop('-')} " }.join
  end

  # `--ai-context` takes an optional value, so it must not be marked `-r`:
  # fish would then refuse to complete anything else until one is typed.
  private def requires_value?(flag : Noir::CLI::ScanFlags::Flag) : Bool
    flag.takes_value? && !flag.arg.optional_choice?
  end
end
