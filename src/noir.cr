require "option_parser"
require "colorize"

module Noir
  VERSION = "1.2.1"

  # LAB (#2613) — opt-in parallelism.
  #
  # Crystal 1.21 compiles execution contexts in by default (no `-Dpreview_mt`;
  # that flag is deprecated and now *rejected* alongside execution contexts).
  # The default context is already `Fiber::ExecutionContext::Parallel`, but it
  # starts with a parallelism of 1, which is why every fiber noir spawns today
  # runs on one thread. Raising it is a runtime call, not a build flag.
  #
  # Gated on an env var so one binary can A/B itself: unset or 1 keeps the
  # current single-threaded behavior exactly, `NOIR_WORKERS=n` resizes, and
  # `NOIR_WORKERS=auto` uses Crystal's own default (which honours
  # `CRYSTAL_WORKERS`, else the effective CPU count).
  def self.setup_parallelism : Int32
    raw = ENV["NOIR_WORKERS"]?
    return 1 if raw.nil? || raw.empty?

    workers =
      if raw == "auto"
        Fiber::ExecutionContext.default_workers_count
      else
        raw.to_i? || 1
      end

    return 1 if workers <= 1
    Fiber::ExecutionContext.default.resize(workers)
    workers
  end
end

Noir.setup_parallelism

require "./cli/router"

Noir::CLI::Router.dispatch(ARGV)
