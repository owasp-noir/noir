require "../javascript/nestjs"

module Analyzer::Typescript
  class Nestjs < Analyzer::Javascript::Nestjs
    analyzer_for "ts_nestjs"

    def analyze
      analyze_with_extensions([".ts", ".tsx"])
    end

    protected def owns_source?(content : String) : Bool
      !content.includes?(MIDWAY_IMPORT)
    end
  end
end
