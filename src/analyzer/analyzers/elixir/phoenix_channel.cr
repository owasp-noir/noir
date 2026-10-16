require "../../../models/analyzer"
require "../../engines/elixir_engine"

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
    analyzer_for "elixir_phoenix_channel"

    # `channel "room:*", RoomChannel` / `channel "room:" <> _, MyApp.RoomChannel`
    # and the `mix format` paren form `channel("room:*", RoomChannel)`, which
    # `mix format` also spreads over several lines past 98 columns:
    # `channel(\n  "room:*",\n  MyApp.RoomChannel\n)`. Run over the whole
    # file (`/m` anchors `^` at each line start); only the keyword has to
    # start its line.
    CHANNEL_DECL = /^[ \t]*channel\s*\(?\s*["']([^"']+)["']\s*,\s*([\w.]+)/m

    # `defmodule MyAppWeb.RoomChannel do`.
    DEFMODULE = /^\s*defmodule\s+([\w.]+)\s+do\b/

    # `handle_in("new_msg", payload, socket)` / `handle_in "ping", _p, socket`.
    # A catch-all `handle_in(_event, ...)` has no string literal, so it is
    # skipped.
    HANDLE_IN = /\bhandle_in\s*\(?\s*["']([^"']+)["']/

    # A channel module opts into the behaviour with one of these.
    CHANNEL_USE = /\buse\s+Phoenix\.Channel\b|\buse\s+[A-Z][\w.]*\s*,\s*:channel\b/

    def analyze
      topics = {} of String => String # channel module (as declared) => topic pattern
      modules = [] of ChannelModule

      files = get_files_by_extension(".ex").reject do |path|
        ElixirEngine.test_path?(base_relative_path(path)) || !File.exists?(path)
      end

      # Pass 1 — topic↔module declarations from socket modules.
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("channel")
        content.scan(CHANNEL_DECL) { |m| topics[m[2]] = m[1] }
      rescue e
        logger.debug "Error scanning Phoenix channel decls in #{path}: #{e}"
        next
      end

      # Pass 2 — channel modules and their handle_in events.
      files.each do |path|
        content = read_file_content(path)
        next unless content.matches?(CHANNEL_USE)
        collect_module(content, path, modules)
      rescue e
        logger.debug "Error analyzing Phoenix channel in #{path}: #{e}"
        next
      end

      emit(modules, topics)
      @result
    end

    private record ChannelModule,
      full_name : String,
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
      modules << ChannelModule.new(name, events, path, module_line)
    end

    # The topic a socket mapped to `mod`: the declared name equal to its
    # full name, else one that is a dotted suffix of it (an `alias`ed
    # `Channels.RoomChannel` or bare `RoomChannel`). Keying by the last
    # segment alone would merge `Client.Channel` and `Gateway.Channel`.
    private def mapped_topic(mod : ChannelModule, topics : Hash(String, String)) : String?
      topics[mod.full_name]? || begin
        topics.each { |declared, topic| return topic if mod.full_name.ends_with?(".#{declared}") }
        nil
      end
    end

    private def emit(modules : Array(ChannelModule), topics : Hash(String, String))
      modules.each do |mod|
        # Skip modules no socket maps to a topic: the `*_web.ex` macro module
        # (`def channel do quote do use Phoenix.Channel …` is the behaviour
        # *definition*), orphan channels, helper modules a mapped channel
        # delegates to (`Channel.Shared`) and `use Phoenix.Channel` samples in
        # docs. A topic invented from the module name can never be joined.
        next unless topic = mapped_topic(mod, topics)

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
  end
end
