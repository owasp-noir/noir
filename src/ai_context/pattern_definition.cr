module NoirAIContext
  # Declarative detection rule shared by every catalog in `Patterns`.
  #
  # A rule pairs a `kind` label (the AIContextEntry kind it raises) with
  # two regex sets: `name_patterns` match against a callee / parameter
  # name, `source_patterns` match against a source snippet. When either
  # set hits, the matcher emits an entry of `kind` at `confidence`.
  class PatternDefinition
    getter kind : String
    getter description : String
    getter confidence : Int32
    getter name_patterns : Array(Regex)
    getter source_patterns : Array(Regex)

    def initialize(@kind : String,
                   @description : String,
                   @confidence : Int32,
                   *,
                   @name_patterns : Array(Regex) = [] of Regex,
                   @source_patterns : Array(Regex) = [] of Regex)
    end
  end
end
