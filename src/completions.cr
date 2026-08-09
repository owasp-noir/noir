# Shell completion scripts for the v1 `noir` CLI.
#
# v1 introduces subcommands (scan, list, cache, config, rules, completion,
# version, help) on top of the v0 flag-only surface. Completions are
# subcommand-aware: typing `noir <TAB>` lists the verbs; typing `noir scan
# <TAB>` falls back to scan-specific paths/flags. The v0 flag set is still
# completed under `noir scan` (and under bare `noir` for users who haven't
# switched to the verb form).
#
# One generator per shell, each in its own file, all rendering the same two
# tables: `Noir::CLI::Catalog` (verbs and their sub-actions) and
# `Noir::CLI::ScanFlags` (scan's flag surface). Adding a flag or a
# subcommand is an edit to a table, not to four scripts.
require "./completions/bash"
require "./completions/elvish"
require "./completions/fish"
require "./completions/zsh"
