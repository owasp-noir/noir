require "../../../models/detector"

module Detector::Elixir
  class Plug < Detector
    detector_for "elixir_plug", extensions: %w[.ex .exs], basenames: %w[mix.exs]

    # `forward "/api", to: SomeRouter` — Plug.Router's mount macro, in the
    # bare and parenthesized call forms.
    #
    # The marker this replaces was `"forward "` AND `"do:"`, and neither
    # half is Plug's: `do:` is Elixir's one-line function body and appears
    # in nearly every module, while `forward` is an ordinary identifier. Any
    # context module with a `forward` variable and a `def …, do: …` was
    # detected as Plug, so a plain Phoenix/Ecto project ran the Plug
    # analyzer over its whole tree for nothing.
    #
    # `to:` is matched anywhere after the path rather than as the first
    # option, because `forward/2` takes `:host`, `:init_opts`, `:private`
    # and `:assigns` in any order (`forward "/", host: "api.", to: Api`).
    FORWARD_RE = /(?:^|\n)[ \t]*forward[ \t(]+["'][^"'\n]*["'][^\n]*\bto:/

    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a mix.exs file with Plug dependency
      if filename.includes?("mix.exs")
        return file_contents.includes?("{:plug,") || file_contents.includes?("plug:")
      end

      # Check for Plug-specific patterns in Elixir files
      if filename.ends_with?(".ex") || filename.ends_with?(".exs")
        # Look for Plug router modules or plug usage
        return file_contents.includes?("use Plug.Router") ||
          file_contents.includes?("plug :match") ||
          file_contents.includes?("plug :dispatch") ||
          file_contents.includes?("Plug.Router") ||
          file_contents.includes?("import Plug.") ||
          content_matches?(file_contents, FORWARD_RE)
      end

      false
    end
  end
end
