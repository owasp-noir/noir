require "../../../models/analyzer"

module Analyzer::Elixir
  # Surfaces Phoenix Channels real-time attack surface as `ws://`
  # endpoints. A channel module (`use Phoenix.Channel` / `use MyAppWeb,
  # :channel`) handles client messages via `handle_in/3` clauses; the
  # socket module maps a topic pattern to the channel with
  # `channel "room:*", RoomChannel`. Each `handle_in` event becomes one
  # endpoint `ws://<topic>/<event>` (bare `ws://<topic>` when a channel has
  # no `handle_in` clauses), method "SEND", protocol "ws" — so the existing
  # WebsocketTagger tags them.
  #
  # Line-scan analyzer. The topic↔module map lives in the socket module
  # while `handle_in` clauses live in the channel module, so `channel`
  # declarations are collected across every `.ex` file first, then joined
  # onto each channel module.
  class PhoenixChannel < Analyzer
    # `channel "room:*", RoomChannel` / `channel "room:" <> _, MyApp.RoomChannel`.
    CHANNEL_DECL = /^\s*channel\s+["']([^"']+)["']\s*,\s*([\w.]+)/

    # `defmodule MyAppWeb.RoomChannel do`.
    DEFMODULE = /^\s*defmodule\s+([\w.]+)\s+do\b/

    # `handle_in("new_msg", payload, socket)` / `handle_in "ping", _p, socket`.
    # A catch-all `handle_in(_event, ...)` has no string literal, so it is
    # skipped.
    HANDLE_IN = /\bhandle_in\s*\(?\s*["']([^"']+)["']/

    # A channel module opts into the behaviour with one of these.
    CHANNEL_USE = /\buse\s+Phoenix\.Channel\b|\buse\s+[A-Z][\w.]*\s*,\s*:channel\b/

    def analyze
      topics = {} of String => String # channel module (short) => topic pattern
      modules = [] of ChannelModule

      files = get_files_by_extension(".ex").reject do |path|
        File.directory?(path) || elixir_test_path?(path) || !File.exists?(path)
      end

      # Pass 1 — topic↔module declarations from socket modules.
      files.each do |path|
        begin
          content = read_file_content(path)
          next unless content.includes?("channel")
          content.each_line do |line|
            if m = line.match(CHANNEL_DECL)
              topics[m[2].split('.').last] = m[1]
            end
          end
        rescue e
          logger.debug "Error scanning Phoenix channel decls in #{path}: #{e}"
          next
        end
      end

      # Pass 2 — channel modules and their handle_in events.
      files.each do |path|
        begin
          content = read_file_content(path)
          next unless content.matches?(CHANNEL_USE)
          collect_module(content, path, modules)
        rescue e
          logger.debug "Error analyzing Phoenix channel in #{path}: #{e}"
          next
        end
      end

      emit(modules, topics)
      @result
    end

    private record ChannelModule,
      name : String,
      events : Array(Tuple(String, Int32)),
      path : String,
      line : Int32

    private def collect_module(content : String, path : String, modules : Array(ChannelModule))
      lines = content.lines
      module_name = nil.as(String?)
      module_line = 1
      events = [] of Tuple(String, Int32)
      seen = Set(String).new

      lines.each_with_index do |line, index|
        if module_name.nil? && (m = line.match(DEFMODULE))
          module_name = m[1]
          module_line = index + 1
        end
        if m = line.match(HANDLE_IN)
          event = m[1]
          unless seen.includes?(event)
            seen << event
            events << {event, index + 1}
          end
        end
      end

      name = module_name || File.basename(path, ".ex")
      modules << ChannelModule.new(name.split('.').last, events, path, module_line)
    end

    private def emit(modules : Array(ChannelModule), topics : Hash(String, String))
      modules.each do |mod|
        mapped = topics[mod.name]?
        # Skip the `*_web.ex` macro module, whose `def channel do quote do
        # use Phoenix.Channel …` matches CHANNEL_USE but is the behaviour
        # *definition*, not a channel: it is never mapped to a topic and has
        # no handle_in clauses. Same guard drops any orphan channel not
        # wired to a socket.
        next if mapped.nil? && mod.events.empty?

        # Prefer the topic the socket module mapped to this channel; fall
        # back to the module's short name when no `channel` declaration is
        # in scope but the module does define events.
        topic = mapped || mod.name

        if mod.events.empty?
          @result << build_endpoint("ws://#{topic}", mod.path, mod.line)
          next
        end

        mod.events.each do |event, line|
          @result << build_endpoint("ws://#{topic}/#{event}", mod.path, line)
        end
      end
    end

    private def build_endpoint(url : String, path : String, line : Int32) : Endpoint
      ep = Endpoint.new(url, "SEND", Details.new(PathInfo.new(path, line)))
      ep.protocol = "ws"
      ep
    end

    # ExUnit's `*_test.exs` convention (mirrors ElixirEngine.test_path?).
    private def elixir_test_path?(path : String) : Bool
      File.basename(path).ends_with?("_test.exs")
    end
  end
end
