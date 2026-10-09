require "../javascript/nestjs"

module Analyzer::Typescript
  class Nestjs < Analyzer::Javascript::Nestjs
    analyzer_for "ts_nestjs"

    # Midway, routing-controllers and Ts.ED spell their decorators
    # `@Controller` / `@Get` too; their own analyzers claim those files.
    FOREIGN_CONTROLLER_RE = /@midwayjs\/|(?:\bfrom|\brequire\s*\()\s*['"](?:routing-controllers['"]|@tsed\/(?:common|schema|di|platform-))/

    def analyze
      analyze_with_extensions([".ts", ".tsx"])
    end

    protected def owns_source?(content : String) : Bool
      !content.matches?(FOREIGN_CONTROLLER_RE)
    end
  end
end
