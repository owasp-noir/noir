require "../cli/catalog"
require "../cli/scan_flags"

# Native Elvish (https://elv.sh) completion. Wires the noir verb surface into
# `$edit:completion:arg-completer` so `noir <Tab>` lists the subcommands,
# `noir <verb> <Tab>` lists that verb's sub-actions, and `noir scan <Tab>`
# falls back to filesystem path completion.
#
# Install:
#   noir completion elvish > ~/.config/elvish/lib/noir.elv
# then add `use noir` to ~/.config/elvish/rc.elv.
module Noir::Completions::Elvish
  extend self

  def script : String
    <<-SCRIPT
      # Noir v1 — Elvish tab-completion
      #
      # Save this file to ~/.config/elvish/lib/noir.elv and add
      #   use noir
      # to your ~/.config/elvish/rc.elv.

      use str

      var commands = [#{Noir::CLI::Catalog::NAMES.join(" ")}]
      #{action_variables}
      var scan-flags = [
      #{flag_lines}
      ]

      set edit:completion:arg-completer[noir] = {|@cmd|
        var n = (count $cmd)
        var last = $cmd[-1]
        if (== $n 2) {
          put $@commands
        } else {
          var verb = $cmd[1]
          # v0 compat: a leading flag (e.g. `noir -b ./path`) means the
          # whole invocation is an implicit `scan`, so treat it that way.
          if (or (eq $verb scan) (str:has-prefix $verb -)) {
            if (str:has-prefix $last -) {
              put $@scan-flags
            } else {
              edit:complete-filename $last
            }
          } elif (== $n 3) {
      #{verb_branches}
          }
        }
      }
      SCRIPT
  end

  # One `var <verb>-args` per verb with a fixed vocabulary. `help` completes
  # the verb list, which `commands` already holds.
  private def action_variables : String
    named_vocabularies.map { |(name, values)| "var #{name}-args = [#{values.join(" ")}]" }.join("\n")
  end

  private def verb_branches : String
    entries = Noir::CLI::Catalog.completable.reject { |(_, values)| values.empty? }

    String.build do |io|
      entries.each_with_index do |(name, _), index|
        target = name == "help" ? "commands" : "#{name}-args"
        io << "      if" if index.zero?
        io << " elif" unless index.zero?
        io << " (eq $verb " << name << ") {\n"
        io << "        put $@" << target << "\n"
        io << "      }"
      end
    end
  end

  private def named_vocabularies : Array(Tuple(String, Array(String)))
    Noir::CLI::Catalog.completable.reject { |(name, values)| values.empty? || name == "help" }
  end

  # Eight flags per line keeps the emitted array readable without wrapping
  # in a narrow terminal.
  private def flag_lines : String
    Noir::CLI::ScanFlags::NAMES.each_slice(8).map { |chunk| "  #{chunk.join(" ")}" }.join("\n")
  end
end
