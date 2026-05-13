require "../javascript/nestjs"

module Analyzer::Typescript
  class Nestjs < Analyzer::Javascript::Nestjs
    def analyze
      analyze_with_extensions([".ts", ".tsx"])
    end
  end
end
