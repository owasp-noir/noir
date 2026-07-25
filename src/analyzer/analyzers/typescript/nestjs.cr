require "../javascript/nestjs"

module Analyzer::Typescript
  class Nestjs < Analyzer::Javascript::Nestjs
    analyzer_for "ts_nestjs"

    def analyze
      analyze_with_extensions([".ts", ".tsx"])
    end
  end
end
