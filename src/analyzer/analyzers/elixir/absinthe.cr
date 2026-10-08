require "../../engines/elixir_engine"
require "../specification/graphql_sdl_parser"
require "../../../utils/url_path"

module Analyzer::Elixir
  # Absinthe (https://hexdocs.pm/absinthe) code-first GraphQL schemas. Each
  # root field — `field` inside a schema's `query`/`mutation`/`subscription`
  # block, an `extend object(:query)` block, or an `object` pulled in with
  # `import_fields` — becomes one endpoint in the shape the SDL analyzers emit.
  #
  # The root blocks live in the `use Absinthe.Schema` module while the
  # imported objects usually sit in `use Absinthe.Schema.Notation` modules in
  # other files, so every file is collected first and the imports are
  # resolved globally afterwards.
  class Absinthe < ElixirEngine
    analyzer_for "elixir_absinthe"

    ROOT_KINDS = {"query" => "Query", "mutation" => "Mutation", "subscription" => "Subscription"}
    # `Absinthe.Schema`'s `@default_query_name` and siblings.
    DEFAULT_ROOT_NAMES = {"Query" => "RootQueryType", "Mutation" => "RootMutationType", "Subscription" => "RootSubscriptionType"}

    # `query do` / `query name: "RootQuery" do` / `mutation(name: "M") do`,
    # matched on the string-stripped line (the name is read off the raw one).
    ROOT_OPEN = /^\s*(query|mutation|subscription)\s*(?:\(?\s*name:\s*\)?\s*)?do\s*$/
    # `extend object(:query) do` / `extend object :mutation do`.
    EXTEND_ROOT = /^\s*extend\s+object\s*\(?\s*:(query|mutation|subscription)\s*\)?\s*do\s*$/
    OBJECT_OPEN = /^\s*object\s*\(?\s*:(\w+)\b.*\bdo\s*$/
    # `field :posts, …` or Absinthe.Relay's `connection field :posts, node_type: :post`.
    FIELD       = /^\s*(connection\s+)?field\s*\(?\s*:(\w+)(.*)$/
    ARG         = /^\s*arg\s*\(?\s*:(\w+)(.*)$/
    IMPORT      = /^\s*import_fields\s*\(?\s*:(\w+)/
    NAME_OPTION = /\bname:\s*"([^"]+)"/
    TYPE_TOKEN  = /\bnon_null\b|\blist_of\b|:(\w+)|\)/
    SCOPE       = /^\s*scope\s*\(?\s*"([^"]*)"/
    # `forward "/api", Absinthe.Plug, schema: …` (Phoenix) or
    # `forward "/api", to: Absinthe.Plug, …` (Plug.Router). The GraphiQL
    # plug (`Absinthe.Plug.GraphiQL`) is the IDE, not the API mount.
    FORWARD = /^\s*forward\s*\(?\s*"([^"]*)"\s*,\s*(?:to:\s*)?Absinthe\.Plug\b(?!\.)/

    # Arguments Absinthe.Relay adds to every `connection field`.
    RELAY_PAGINATION_ARGS = [
      {name: "after", type: "String"}, {name: "first", type: "Int"},
      {name: "before", type: "String"}, {name: "last", type: "Int"},
    ]

    SCALARS = {"string" => "String", "integer" => "Int", "float" => "Float", "boolean" => "Boolean", "id" => "ID"}

    record Field, name : String, return_type : String, args : Array(NamedTuple(name: String, type: String)),
      path : String, line : Int32

    # A `query`/`mutation`/`subscription` block (`root`, keyed by its kind)
    # or an `object` block (keyed by its identifier): its own fields plus the
    # objects it `import_fields`.
    record Block, key : String, root : Bool, type_name : String?,
      fields : Array(Field), imports : Array(String)

    record FileFacts, blocks : Array(Block), mount : String?, passthrough : Bool

    @camelize = true

    def analyze
      per_file = ordered_file_scan { |path| collect(path) }

      mount = per_file.compact_map(&.mount).first? || Analyzer::Specification::GraphqlSdlParser::DEFAULT_GRAPHQL_PATH
      # `adapter: Absinthe.Adapter.Passthrough` / `Underscore` on the plug (or
      # `Absinthe.run`) keep the schema's snake_case names on the wire.
      @camelize = per_file.none?(&.passthrough)

      roots = [] of Block
      # ponytail: one global object namespace; two schemas in one repo that
      # reuse an object identifier resolve to the later file's object.
      objects = {} of String => Block
      per_file.each do |facts|
        facts.blocks.each do |block|
          if block.root
            roots << block
          else
            objects[block.key] = block
          end
        end
      end

      type_names = DEFAULT_ROOT_NAMES.dup
      roots.each { |root| root.type_name.try { |name| type_names[root.key] = name } }

      roots.each do |root|
        each_field(root, objects, Set(String).new) do |field|
          args = field.args.map { |arg| {name: external(arg[:name]), type: arg[:type]} }
          result << Analyzer::Specification::GraphqlSdlParser.field_endpoint(
            field.path, field.line, root.key, external(field.name), args, field.return_type,
            "elixir_absinthe", mount, type_names[root.key])
        end
      end
      result
    end

    # Collection replaces the per-file walk; `analyze` drives everything.
    def analyze_file(path : String) : Array(Endpoint)
      [] of Endpoint
    end

    private def each_field(block : Block, objects : Hash(String, Block), seen : Set(String), &yield_field : Field ->)
      block.fields.each { |field| yield_field.call(field) }
      block.imports.each do |id|
        next unless seen.add?(id)
        if object = objects[id]?
          each_field(object, objects, seen, &yield_field)
        end
      end
    end

    private def collect(path : String) : FileFacts?
      content = read_file_content(path)
      # Type modules often `use` an app-local wrapper around
      # `Absinthe.Schema.Notation`, so an `object` alone has to admit a file.
      return unless content.includes?("Absinthe") || content.includes?("object")

      blocks = [] of Block
      mount = nil.as(String?)
      # The open block / `scope`s with the depth their body sits at; each
      # closes once depth drops below it.
      current = nil.as(Tuple(Block, Int32)?)
      scopes = [] of Tuple(String, Int32)
      depth = 0

      content.each_line.with_index do |raw, index|
        # Comments and string literals stripped; the few string-valued
        # options (`name: "…"`, scope and forward paths) are read off `raw`.
        line = Noir::ElixirCalleeExtractor.strip_comment(raw)

        if current
          block, body_depth = current
          if depth == body_depth
            if m = line.match(FIELD)
              name = raw.match(NAME_OPTION).try(&.[1]) || m[2]
              block.fields << if m[1]?
                # ponytail: always the default `paginate: :both` arguments.
                Field.new(name, "#{graphql_type(m[3])}Connection", RELAY_PAGINATION_ARGS.dup, path, index + 1)
              else
                Field.new(name, graphql_type(m[3]), [] of NamedTuple(name: String, type: String), path, index + 1)
              end
            elsif m = line.match(IMPORT)
              block.imports << m[1]
            end
          elsif depth > body_depth && (field = block.fields.last?) && (m = line.match(ARG))
            field.args << {name: m[1], type: graphql_type(m[2])}
          end
        elsif m = line.match(ROOT_OPEN)
          current = {Block.new(ROOT_KINDS[m[1]], true, raw.match(NAME_OPTION).try(&.[1]), [] of Field, [] of String), depth + 1}
        elsif m = line.match(EXTEND_ROOT)
          current = {Block.new(ROOT_KINDS[m[1]], true, nil, [] of Field, [] of String), depth + 1}
        elsif m = line.match(OBJECT_OPEN)
          current = {Block.new(m[1], false, nil, [] of Field, [] of String), depth + 1}
        elsif raw.includes?("scope") && (m = raw.match(SCOPE))
          scopes << {m[1], depth + 1}
        elsif mount.nil? && raw.includes?("Absinthe.Plug") && (m = raw.match(FORWARD))
          prefix = scopes.reduce("") { |acc, scope| Noir::URLPath.join_absorbing(acc, scope[0]) }
          mount = Noir::URLPath.join_rooted(prefix, m[1].lstrip('/'))
        end

        depth += elixir_block_depth_delta(raw)
        if current && depth < current[1]
          blocks << current[0]
          current = nil
        end
        scopes.pop if (scope = scopes.last?) && depth < scope[1]
      end

      passthrough = content.includes?("Absinthe.Adapter.Passthrough") || content.includes?("Absinthe.Adapter.Underscore")
      return if blocks.empty? && mount.nil? && !passthrough
      FileFacts.new(blocks, mount, passthrough)
    end

    # Absinthe's type expression (`non_null(list_of(:post))`, `:string`) as
    # a GraphQL type string (`[Post]!`, `String`). The first atom that closes
    # every open wrapper ends the expression, so trailing options
    # (`default_value: :asc`) are ignored.
    private def graphql_type(expr : String) : String
      closers = [] of String
      String.build do |io|
        expr.scan(TYPE_TOKEN) do |m|
          case m[0]
          when "non_null"
            closers << "!"
          when "list_of"
            io << '['
            closers << "]"
          when ")"
            break if closers.empty?
            io << closers.pop
            break if closers.empty?
          else
            io << (SCALARS[m[1]]? || camelize(m[1], upper: true))
            break if closers.empty?
          end
        end
        closers.reverse_each { |closer| io << closer }
      end
    end

    # `Absinthe.Adapter.LanguageConventions` (the default adapter) sends
    # `create_post` as `createPost`; arguments are converted the same way.
    private def external(name : String) : String
      @camelize ? camelize(name, upper: false) : name
    end

    # `Absinthe.Utils.camelize`: `Macro.camelize` with a leading `_` kept.
    private def camelize(name : String, upper : Bool) : String
      return "_#{camelize(name[1..], upper)}" if name.starts_with?('_')
      camel = name.split('_', remove_empty: true).join { |part| "#{part[0].upcase}#{part[1..]}" }
      return camel if upper || camel.empty?
      "#{camel[0].downcase}#{camel[1..]}"
    end
  end
end
