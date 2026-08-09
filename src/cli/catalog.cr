# The `noir` command surface: which top-level verbs exist, what each one
# does, and the fixed vocabulary that follows it.
#
# Every consumer reads it from here — the router's dispatch, each command's
# `-h` page, `noir help`, and the zsh/bash/fish/elvish completion
# generators. Before this module the same six lists were written out in as
# many places (`KNOWN_COMMANDS`, `KNOWN_HELP_TARGETS`, each command's
# `ACTIONS`, and once per shell in `completions.cr`), with nothing linking
# them: a renamed action stayed "valid" in three completion scripts, and a
# new subcommand had to be remembered in six files or it silently went
# uncompleted.
module Noir::CLI::Catalog
  # Sub-action vocabularies. Each command module re-exports the one it owns,
  # so `CacheCommand::ACTIONS` still reads naturally at its use site while
  # the list itself lives in one place.
  LIST_SUBJECTS  = %w[techs taggers formats]
  CACHE_ACTIONS  = %w[info clear purge]
  CONFIG_ACTIONS = %w[show edit init path]
  RULES_ACTIONS  = %w[list update path]
  SHELLS         = %w[zsh bash fish elvish]

  # One top-level verb.
  #
  # `actions` is the fixed set of words that may follow the verb; it doubles
  # as the argument shape shown by `noir help` (`cache info | clear |
  # purge`). `args` overrides that for verbs whose argument isn't a fixed
  # vocabulary.
  record Command,
    name : String,
    summary : String,
    actions : Array(String) = [] of String,
    args : String? = nil do
    # What `noir help` prints after the verb.
    def usage_args : String
      args || actions.join(" | ")
    end
  end

  COMMANDS = [
    Command.new("scan", "Discover endpoints in one or more codebases", args: "[PATHS...]"),
    Command.new("list", "Enumerate built-in catalogs", LIST_SUBJECTS),
    Command.new("cache", "Manage the on-disk LLM response cache", CACHE_ACTIONS),
    Command.new("config", "Manage the user-level YAML configuration", CONFIG_ACTIONS),
    Command.new("rules", "Manage the passive-scan rules repository", RULES_ACTIONS),
    Command.new("completion", "Generate a shell completion script", SHELLS),
    Command.new("version", "Print version (or full build details)", args: "[--verbose]"),
    Command.new("help", "Show this overview or a command's help", args: "[command]"),
  ]

  NAMES = COMMANDS.map(&.name)

  # The verb → next-word vocabulary pairs a completion script needs, in the
  # order its `case` should test them. `scan` is excluded: it is the
  # fallback branch every shell falls through to, and its next word is a
  # path or a flag rather than a fixed word.
  #
  # `help` completes the verb list itself, which is why this can't simply be
  # `Command#actions`.
  def self.completable : Array(Tuple(String, Array(String)))
    COMMANDS.reject { |command| command.name == "scan" }.map do |command|
      {command.name, command.name == "help" ? NAMES : command.actions}
    end
  end
end
