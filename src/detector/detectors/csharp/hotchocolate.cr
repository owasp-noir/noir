require "../../../models/detector"

module Detector::CSharp
  # Detects HotChocolate (https://chillicream.com/docs/hotchocolate): a
  # `HotChocolate*` package reference, a `HotChocolate` namespace import, or
  # the `AddGraphQLServer()` registration. Gates the code-first GraphQL
  # analyzer, so a plain class named `Query` never fires without it.
  class HotChocolate < Detector
    detector_for "cs_hotchocolate", extensions: %w[.cs .csproj .props .targets]

    SOURCE_MARKER  = /\busing\s+(?:static\s+)?HotChocolate\b|\bAddGraphQLServer\s*\(/
    PACKAGE_MARKER = /Include\s*=\s*["']HotChocolate\b/

    def detect(filename : String, file_contents : String) : Bool
      return content_matches?(file_contents, SOURCE_MARKER) if filename.ends_with?(".cs")
      content_matches?(file_contents, PACKAGE_MARKER)
    end
  end
end
