require "../../../models/detector"

module Detector::Elixir
  class Phoenix < Detector
    # Phoenix routers rarely write `use Phoenix.Router` directly; the
    # generated convention is `use MyAppWeb, :router`, where the
    # `:router` clause of the app's `*_web.ex` macro injects
    # `Phoenix.Router`. Match that `use _, :router` shape so real
    # routers register even when the literal `Phoenix.Router` never
    # appears in the file.
    ROUTER_USE_REGEX = /\buse\s+[A-Z]\w*(?:\.[A-Z]\w*)*\s*,\s*:router\b/

    def detect(filename : String, file_contents : String) : Bool
      basename = File.basename(filename)

      # The mix manifest is the most reliable signal: a real Phoenix
      # project always declares the core `{:phoenix, ...}` dependency.
      # The previous check looked for the literal `ElixirPhoenix`,
      # which only ever matched the test fixture's module name, so
      # every real-world app silently fell through to the Plug
      # analyzer (losing scope prefixes, `resources` expansion, and
      # controller param/callee extraction). Require the `{:phoenix,`
      # tuple specifically so sibling deps like `{:phoenix_ecto, ...}`
      # or `{:phoenix_live_view, ...}` don't masquerade as the core.
      if basename == "mix.exs"
        return file_contents.includes?("{:phoenix,") ||
          file_contents.includes?("{ :phoenix,")
      end

      # A router module is an equally strong signal when the mix file
      # isn't in scope (e.g. `--include-path` runs over `lib/` only).
      if filename.ends_with?(".ex") || filename.ends_with?(".exs")
        return file_contents.includes?("Phoenix.Router") ||
          file_contents.matches?(ROUTER_USE_REGEX)
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".ex") || filename.ends_with?(".exs") || File.basename(filename) == "mix.exs"
    end

    def set_name
      @name = "elixir_phoenix"
    end
  end
end
