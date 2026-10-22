require "../../../miniparsers/python_graphql_extractor_ts"
require "../../engines/python_engine"
require "../specification/graphql_sdl_parser"
require "../../../detector/detectors/python/graphene"

module Analyzer::Python
  class Graphene < PythonEngine
    analyzer_for "python_graphene"

    # Reference: https://docs.graphene-python.org/en/latest/types/schema/
    #
    # One endpoint per field of the `ObjectType`s bound by
    # `graphene.Schema(query=, mutation=, subscription=)`, including fields
    # inherited from mixins in other modules. A field is a class attribute
    # holding a mounted type (`graphene.String(arg=...)`,
    # `graphene.Field(T, arg=...)`); its extra keyword arguments are the
    # GraphQL arguments. `CreateX.Field()` takes them from the mutation's
    # `class Arguments`, and relay `ClientIDMutation`s from one `input`.

    TAGGER = "graphene_analyzer"
    alias X = Noir::PythonGraphqlExtractor

    # An extra keyword argument is a GraphQL argument only when it holds a
    # mounted type (a call: graphene rejects anything else), so `name="x"`,
    # `required=True` and app-specific options are not; these are options
    # that may still be spelled as a call (`description=_("...")`).
    NOT_ARGS          = %w[description resolver deprecation_reason default_value args]
    WRAPPERS          = %w[Field Argument InputField Dynamic DjangoListField]
    CONNECTION_FIELDS = %w[ConnectionField RelayConnectionField DjangoConnectionField DjangoFilterConnectionField SQLAlchemyConnectionField MongoengineConnectionField]
    CONNECTION_ARGS   = [{name: "before", type: "String"}, {name: "after", type: "String"}, {name: "first", type: "Int"}, {name: "last", type: "Int"}]
    CLIENT_ID_BASE    = /ClientIDMutation|FormMutation|SerializerMutation/
    DICT_ENTRY        = /\A["'](\w+)["']\s*:\s*(.+)\z/m

    def analyze
      outlines = ordered_parallel_analyze(python_source_files) do |path|
        source = read_file_content(path)
        X.outline(path, source, source.includes?("graphene") && source.matches?(Detector::Python::Graphene::IMPORT_RE))
      end
      index = X::Index.new(outlines)

      seen = Set(::String).new
      # Each app's schema binding and mount on their own.
      outlines.group_by { |outline| python_project_root(outline.path) }.each_value do |group|
        mount = index.mount_path(group) || Specification::GraphqlSdlParser::DEFAULT_GRAPHQL_PATH
        index.roots(group) { |c| index.lineage(c).any? { |k| index.library?(k) && k.bases.any?(&.includes?("ObjectType")) } }.each do |(kind, klass, camel)|
          index.members(klass).each do |member|
            next if member.params
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
      value = member.value || return
      callee = X.callee(value) || return
      positional, keywords = X.call_args(value) || return
      name = X.string_literal(keywords["name"]?) || (camel ? X.camel_case(member.name) : member.name)
      args = [] of NamedTuple(name: ::String, type: ::String)
      receiver, _, last = callee.rpartition('.')

      if last == "Field" && receiver.ends_with?("Node")
        # `relay.Node.Field(T)` fetches any node by its global ID.
        args << {name: "id", type: "ID!"}
        return {name, args, positional.first?.try { |t| graphql_type(t) } || "Node"}
      elsif last == "Field" && !receiver.empty? && (mutation = index.resolve_class(member.path, receiver))
        return {name, mutation_args(mutation, index, camel), mutation.name}
      end

      if CONNECTION_FIELDS.includes?(last)
        args.concat(CONNECTION_ARGS)
        args << {name: "offset", type: "Int"} if last.starts_with?("Django")
      end
      keywords["args"]?.try { |dict| dict_entries(dict).each { |(k, v)| args << argument(k, v, camel) } }
      keywords.each do |key, val|
        next if NOT_ARGS.includes?(key) || X.callee(val).nil?
        args << argument(key, val, camel)
      end
      {name, args, graphql_type(value)}
    end

    private def argument(key : ::String, value : ::String, camel : Bool)
      override = X.call_args(value).try { |(_, kw)| X.string_literal(kw["name"]?) }
      {name: override || (camel ? X.camel_case(key) : key), type: graphql_type(value)}
    end

    # `class Arguments:` of the mutation (or a base), else the single
    # `input` of a relay `ClientIDMutation`, else the legacy `class Input:`.
    private def mutation_args(mutation : X::ClassDecl, index : X::Index, camel : Bool)
      lineage = index.lineage(mutation)
      inputs = lineage.reverse.compact_map(&.inner["Arguments"]?)
      if inputs.empty?
        if lineage.any?(&.bases.any?(&.matches?(CLIENT_ID_BASE)))
          return [{name: "input", type: "#{mutation.name}Input!"}]
        end
        inputs = lineage.reverse.compact_map(&.inner["Input"]?)
      end
      (inputs.first?.try(&.members) || [] of X::Member).compact_map do |m|
        value = m.value
        argument(m.name, value, camel) if value && X.callee(value)
      end
    end

    private def dict_entries(dict : ::String) : Array({::String, ::String})
      text = dict.strip
      return [] of {::String, ::String} unless text.starts_with?('{') && text.ends_with?('}')
      Noir::TopLevelSplit.split(text[1...-1], ',', Noir::TopLevelSplit::Rules::PYTHON).compact_map do |entry|
        entry.strip.match(DICT_ENTRY).try { |m| {m[1], m[2]} }
      end
    end

    # A mounted graphene type as a GraphQL type reference:
    # `graphene.List(graphene.String, required=True)` => `[String]!`.
    private def graphql_type(text : ::String) : ::String
      text = text.strip
      text = text.lchop("lambda").lstrip.lchop(':').strip if text.starts_with?("lambda")
      if literal = X.string_literal(text)
        return literal.rpartition('.').last
      end
      callee = X.callee(text) || return text.rpartition('.').last
      positional, keywords = X.call_args(text) || return ""
      last = callee.rpartition('.').last
      inner = positional.first?.try { |t| graphql_type(t) } || ""
      core = case last
             when "List"    then "[#{inner}]"
             when "NonNull" then inner.rchop('!')
             when .in?(WRAPPERS), .in?(CONNECTION_FIELDS)
               inner
             else last
             end
      last == "NonNull" || keywords["required"]? == "True" ? "#{core.rchop('!')}!" : core
    end
  end
end
