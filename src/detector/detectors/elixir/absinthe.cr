require "../../../models/detector"

module Detector::Elixir
  # Detects Absinthe code-first GraphQL schemas: the schema module
  # (`use Absinthe.Schema`) or a type module (`use Absinthe.Schema.Notation`).
  class Absinthe < Detector
    detector_for "elixir_absinthe", extensions: %w[.ex .exs]

    USE_SCHEMA = /^\s*use\s+Absinthe\.Schema\b/m

    def detect(filename : String, file_contents : String) : Bool
      file_contents.includes?("Absinthe.Schema") && content_matches?(file_contents, USE_SCHEMA)
    end
  end
end
