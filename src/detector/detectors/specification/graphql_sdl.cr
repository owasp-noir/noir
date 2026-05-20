require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class GraphqlSdl < Detector
    # Top-level SDL signals — distinguishes a schema document from an
    # operation document (which the file_analyzers/graphql_analyzer handles).
    SDL_SIGNAL = /^[\s]*(?:extend\s+)?(?:type|input|interface|union|enum|scalar|directive|schema)\b/m

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.match(SDL_SIGNAL)

      locator = CodeLocator.instance
      locator.push("graphql-sdl", filename)
      true
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".graphql") ||
        filename.ends_with?(".gql") ||
        filename.ends_with?(".graphqls")
    end

    def set_name
      @name = "graphql_sdl"
    end

    # Registers every SDL path in `CodeLocator` for the analyzer pass.
    # Must keep running after the first match so all schema files get picked up.
    def idempotent? : Bool
      false
    end
  end
end
