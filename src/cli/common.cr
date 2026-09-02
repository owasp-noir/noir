require "colorize"
require "log"
require "./catalog"

module Noir::CLI
  # Known top-level verbs. The router falls back to `scan` when ARGV[0]
  # is not one of these (preserving the `noir -b ./app` v0 usage pattern).
  KNOWN_COMMANDS = Catalog::NAMES

  # Point Crystal's global `Log` at STDERR.
  #
  # The stdlib configures that logger, at the bottom of its own `log.cr`,
  # with a `Log::IOBackend` whose IO defaults to **STDOUT** — and stdout is
  # where Noir's report goes. So anything logged through the global `Log`,
  # by Noir or by a shard Noir pulls in, lands in the middle of the
  # `-f json` / `-f sarif` / `-f yaml` document and breaks every downstream
  # parser.
  #
  # Not hypothetical, and not limited to code this repo owns:
  #
  #   * the `har` shard warns through the global `Log` for an unparsable
  #     `startedDateTime` or cookie `expires`, so a browser capture whose
  #     timestamps are not ISO-8601 printed a WARN line *and a full Crystal
  #     backtrace* ahead of the JSON — `noir scan ./captures -f json | jq .`
  #     died with `Invalid numeric literal at line 1, column 14`;
  #   * `NOIR_ACP_RAW_LOG=1` deliberately un-mutes the `acp` shard's
  #     `acp.client` / `acp.transport` sources, which then wrote their
  #     protocol diagnostics to the same stdout.
  #
  # Every diagnostic Noir writes itself already goes to STDERR through
  # `NoirLogger`. This makes the same invariant hold for the code Noir does
  # not own, once, at the process entry point.
  #
  # The severity threshold is left exactly where the stdlib default puts it
  # (`Info`) — this changes the stream, not what gets logged — and is
  # deliberately *not* wired to `LOG_LEVEL`, so a variable that happens to
  # be exported for some other tool cannot start adding lines to a Noir run.
  #
  # `Sync` rather than the default async dispatcher: these are rare
  # diagnostics, and an async backend flushes from its own fiber, which can
  # reorder them against — or lose them behind — `NoirLogger`'s STDERR
  # writes and the process exiting.
  def self.route_library_logs_to_stderr! : Nil
    ::Log.setup(
      ::Log::Severity::Info,
      ::Log::IOBackend.new(STDERR, dispatcher: ::Log::DispatchMode::Sync)
    )
  end

  # Disable Crystal's Colorize globally when the user asks for plain
  # output via `--no-color` or the `NO_COLOR` env var. Applied at the
  # router layer so every subcommand (list / cache / config / rules /
  # completion / version / help / scan) picks it up. Scan's own parser
  # still sees `--no-color` and threads it through NoirRunner for the
  # in-scan logger.
  def self.apply_global_color_flag!(argv : Array(String)) : Nil
    if no_color_env? || argv.includes?("--no-color")
      Colorize.enabled = false
    end
  end

  # NO_COLOR follows the convention at https://no-color.org: any
  # non-empty value disables color, with the explicit exception of "0".
  def self.no_color_env? : Bool
    value = ENV["NO_COLOR"]?
    return false if value.nil? || value.empty?
    value != "0"
  end

  # Flags the router itself owns, valid anywhere on the command line —
  # including *before* the verb, which is where `noir help` documents them
  # ("Strip ANSI color from every command's output"). `verb_index` is what
  # lets that placement work: without it the router only ever looked at
  # `argv.first`, so `noir --no-color scan ./app` fell through to the v0
  # bare-flag path and died with `Base path does not exist: scan`.
  GLOBAL_FLAGS = ["--no-color", "--no-spinner"]

  # Index of the first token that is not one of the leading global flags,
  # i.e. where the subcommand verb would be. Returns `argv.size` when argv
  # holds nothing but global flags.
  def self.verb_index(argv : Array(String)) : Int32
    index = 0
    while index < argv.size && GLOBAL_FLAGS.includes?(argv[index])
      index += 1
    end
    index
  end

  def self.die(message : String, code : Int32 = 1) : NoReturn
    STDERR.puts "ERROR: #{message}".colorize(:red)
    exit(code)
  end

  # Shared accent helpers so every `-h` page styles its section labels
  # and inline command names the same way. Green for headers (USAGE,
  # SUBJECTS, ACTIONS, OPTIONS, ...). Cyan for the named items inside.
  def self.section(label : String) : String
    label.colorize(:green).to_s
  end

  def self.name(label : String) : String
    label.colorize(:cyan).to_s
  end
end
