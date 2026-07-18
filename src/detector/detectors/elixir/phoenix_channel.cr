require "../../../models/detector"

module Detector::Elixir
  # Detects Phoenix Channels: a channel module (`use Phoenix.Channel` /
  # `use MyAppWeb, :channel`) or a socket module's `channel "topic", Mod`
  # declaration. Gates the Phoenix Channel analyzer, which emits
  # `handle_in` events as `ws://` realtime endpoints. Runs alongside the
  # Phoenix (HTTP router) detector — the two cover different surfaces.
  class PhoenixChannel < Detector
    CHANNEL_MARKER = /\buse\s+Phoenix\.Channel\b|\buse\s+[A-Z][\w.]*\s*,\s*:channel\b|\bchannel\s+["'][^"']+["']\s*,\s*[A-Z]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".ex") || filename.ends_with?(".exs")
      file_contents.matches?(CHANNEL_MARKER)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ex") || filename.ends_with?(".exs")
    end

    def set_name
      @name = "elixir_phoenix_channel"
    end
  end
end
