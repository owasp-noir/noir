require "../../../miniparsers/python_graphql_extractor_ts"
require "../../engines/python_engine"
require "../specification/graphql_sdl_parser"
require "../../../detector/detectors/python/strawberry"

module Analyzer::Python
  class Strawberry < PythonEngine
    analyzer_for "python_strawberry"

    # Reference: https://strawberry.rocks/docs/types/schema
    #
    # One endpoint per field of the root types bound by
    # `strawberry.Schema(query=, mutation=, subscription=)`: methods
    # decorated with `@strawberry.field` / `.mutation` / `.subscription`
    # (arguments from the signature) and annotated attributes, optionally
    # `= strawberry.field(resolver=fn)` (arguments from `fn`). Fields of
    # inherited types and of `merge_types(...)` parts count too.

    TAGGER = "strawberry_analyzer"
    alias X = Noir::PythonGraphqlExtractor

    FIELD_DECORATOR = /\A(?:[\w.]+\.)?(?:field|mutation|subscription)(?:\(|\z)/
    FIELD_CALL      = /\A(?:[\w.]+\.)?(?:field|mutation|subscription)\z/
    TYPE_DECORATOR  = /\A(?:[\w.]+\.)?type(?:\(|\z)/
    NOT_A_FIELD     = /\b(?:ClassVar|Private|InitVar)\b/
    # `self`/`cls`/`root`/`info` by name, `Info` and `Parent` by annotation.
    RESERVED_PARAMS = %w[self cls root info]
    RESERVED_TYPE   = /\b(?:Info|Parent)\b/
    ARGUMENT_NAME   = /\bargument\([^)]*\bname\s*=\s*["'](\w+)["']/
    SCALARS         = {
      "str" => "String", "int" => "Int", "float" => "Float", "bool" => "Boolean",
      "datetime" => "DateTime", "date" => "Date", "time" => "Time",
    }
    LISTS   = %w[list List Sequence Iterable tuple Tuple set Set frozenset]
    STREAMS = %w[AsyncGenerator AsyncIterator AsyncIterable Generator Iterator]
    GENERIC = /\A(?:[\w.]+\.)?(\w+)\[(.*)\]\z/m

    def analyze
      outlines = ordered_parallel_analyze(python_source_files) do |path|
        source = read_file_content(path)
        X.outline(path, source, source.includes?("strawberry") && source.matches?(Detector::Python::Strawberry::IMPORT_RE))
      end
      index = X::Index.new(outlines)

      seen = Set(::String).new
      # Each app's schema binding and mount on their own.
      outlines.group_by { |outline| python_project_root(outline.path) }.each_value do |group|
        mount = index.mount_path(group) || Specification::GraphqlSdlParser::DEFAULT_GRAPHQL_PATH
        index.roots(group) { |c| c.decorators.any?(&.matches?(TYPE_DECORATOR)) }.each do |(kind, klass, camel)|
          index.members(klass).each do |member|
            name, args, returns = field(member, index, camel) || next
            endpoint = Specification::GraphqlSdlParser.field_endpoint(member.path, member.line, kind, name, args,
              returns, TAGGER, mount, klass.name)
            result << endpoint if seen.add?(endpoint.url)
          end
        end
      end
      result
    end

    private def field(member : X::Member, index : X::Index, camel : Bool)
      params = member.params
      returns = member.type_hint
      name = nil
      if params
        decorator = member.decorators.find(&.matches?(FIELD_DECORATOR)) || return
        name = X.call_args(decorator).try { |(_, kw)| X.string_literal(kw["name"]?) }
        returns = member.returns
      else
        call = member.value.try { |v| X.callee(v) }.try(&.matches?(FIELD_CALL))
        return unless returns || call
        return if returns.try(&.matches?(NOT_A_FIELD))
        if call && (value = member.value) && (kw = X.call_args(value).try(&.[1]))
          name = X.string_literal(kw["name"]?)
          if resolver = kw["resolver"]?.try { |r| index.resolve_function(member.path, r) }
            params = resolver.params
            returns ||= resolver.returns
          end
        end
      end

      args = (params || [] of X::Param).compact_map do |param|
        hint = param.type_hint || ""
        next if RESERVED_PARAMS.includes?(param.name) || hint.matches?(RESERVED_TYPE)
        arg_name = hint.match(ARGUMENT_NAME).try(&.[1]) || (camel ? X.camel_case(param.name) : param.name)
        {name: arg_name, type: graphql_type(hint)}
      end
      {name || (camel ? X.camel_case(member.name) : member.name), args, returns.try { |r| graphql_type(r) } || ""}
    end

    # A Python annotation as a GraphQL type reference: `str` => `String!`,
    # `Optional[int]` / `int | None` => `Int`, `list[Book]` => `[Book!]!`.
    private def graphql_type(hint : ::String) : ::String
      text = hint.strip.delete("\"'")
      return "String" if text.empty?
      if (m = text.match(GENERIC)) && m[1] == "Annotated"
        return graphql_type(split(m[2]).first)
      end

      parts = split(text, '|')
      nullable = parts.size > 1 && parts.includes?("None")
      if (m = text.match(GENERIC)) && {"Optional", "Union"}.includes?(m[1])
        parts = split(m[2])
        nullable = m[1] == "Optional" || parts.includes?("None")
      end
      text = (parts - ["None"]).first? || text

      core = if (m = text.match(GENERIC)) && LISTS.includes?(m[1])
               "[#{graphql_type(split(m[2]).first)}]"
             elsif m && STREAMS.includes?(m[1])
               return graphql_type(split(m[2]).first)
             else
               base = text.rpartition('.').last
               SCALARS[base]? || base
             end
      nullable ? core : "#{core}!"
    end

    private def split(text : ::String, delimiter : Char = ',') : Array(::String)
      Noir::TopLevelSplit.split(text, delimiter, Noir::TopLevelSplit::Rules::PYTHON).map(&.strip)
    end
  end
end
