require "../../../models/analyzer"
require "../../../utils/top_level_split"
require "../../engines/ruby_engine"
require "../specification/graphql_sdl_parser"

module Analyzer::Ruby
  # graphql-ruby (code-first GraphQL). The schema lives in Ruby classes, not
  # SDL: `class AppSchema < GraphQL::Schema` binds `query Types::QueryType`
  # (and mutation/subscription), and each root type declares
  # `field :post, PostType do argument :id, ID end`, or delegates to a
  # `resolver:` / `mutation:` class that declares its own `argument`s. Each
  # root field becomes one endpoint in the shape the SDL analyzers emit.
  #
  # Two passes: every `.rb` file is line-scanned into class/module bodies
  # (fields, arguments, includes, superclass), then roots, resolvers and
  # mixins are resolved across files by constant name. Class bodies are
  # closed by indentation, which holds for conventionally formatted Ruby.
  class Graphql < RubyEngine
    analyzer_for "ruby_graphql"

    TAG_SOURCE = "ruby_graphql_analyzer"

    # A file carries something this analyzer reads only if it names
    # graphql-ruby, declares a field/argument, or routes to a GraphQL
    # controller.
    FILE_GATE_RE = /GraphQL::|graphql#|^\s*(?:field|argument)\b/m

    CLASS_RE        = /^\s*(?:class|module)\s+((?:::)?[A-Z][\w:]*)(?:\s*<\s*((?:::)?[A-Z][\w:]*))?/
    FIELD_RE        = /^\s*field[\s(]/
    ARGUMENT_RE     = /^\s*argument[\s(]/
    INCLUDE_RE      = /^\s*(?:include|implements|add_field)\s*\(?\s*((?:::)?[A-Z][\w:]*)/
    GRAPHQL_NAME_RE = /^\s*graphql_name\s*\(?\s*["']([^"']+)["']/
    TYPE_DECL_RE    = /^\s*type\s*\(?\s*([\["'A-Z:].*)$/
    ROOT_RE         = /^\s*(query|mutation|subscription)\s*\(?\s*((?:::)?[A-Z][\w:]*)/
    END_RE          = /^\s*end\b/
    ONE_LINE_END_RE = /;\s*end\s*$/
    DO_TAIL_RE      = /\s+do(?:\s*\|[^|]*\|)?\s*\z/
    CALL_HEAD_RE    = /\A\s*(?:field|argument)\s*(\()?/
    KWARG_RE        = /\A(\w+):(?!:)\s*(.*)\z/m
    SYMBOL_NAME_RE  = /\A:(\w+[?!]?)\z|\A["'](\w+)["']\z/
    NULL_TRUE_RE    = /\Anull:\s*true\z/

    # Rails: `post "/graphql", to: "graphql#execute"` (or the `=>` form).
    MOUNT_RE = /["']([^"'\s]+)["']\s*(?:,\s*to:\s*|=>\s*)["'][\w\/]*graphql#\w+["']/

    ROOT_KINDS     = {"query" => "Query", "mutation" => "Mutation", "subscription" => "Subscription"}
    FALLBACK_ROOTS = {
      "QueryType" => "Query", "Query" => "Query",
      "MutationType" => "Mutation", "Mutation" => "Mutation",
      "SubscriptionType" => "Subscription", "Subscription" => "Subscription",
    }

    # Ruby class names graphql-ruby maps to built-in scalars.
    SCALAR_ALIASES = {"Integer" => "Int"}

    alias Arg = NamedTuple(name: String, type: String)

    private record Field, name : String, type : String, args : Array(Arg), resolver : String?,
      connection : Bool?, path : String, line : Int32

    # A field whose return type is a `*Connection` gets these four arguments.
    CONNECTION_ARGS = [{name: "after", type: "String"}, {name: "before", type: "String"},
                       {name: "first", type: "Int"}, {name: "last", type: "Int"}]

    # `include GraphQL::Types::Relay::HasNodeField` / `HasNodesField` (or the
    # legacy `add_field GraphQL::Types::Relay::NodeField`) add these fields.
    RELAY_NODE_FIELDS = {
      "HasNodeField"  => {"node", [{name: "id", type: "ID!"}], "Node"},
      "HasNodesField" => {"nodes", [{name: "ids", type: "[ID!]!"}], "[Node]!"},
      "NodeField"     => {"node", [{name: "id", type: "ID!"}], "Node"},
      "NodesField"    => {"nodes", [{name: "ids", type: "[ID!]!"}], "[Node]!"},
    }

    # One class/module body. A constant re-opened in several files gets one
    # Unit per opening; resolution merges them.
    private class Unit
      getter name : String
      getter nesting : Array(String)
      getter superclass : String?
      getter path : String
      getter fields = [] of Field
      getter args = [] of Arg
      getter includes = [] of Tuple(String, Int32)
      getter roots = {} of String => String
      property graphql_name : String?
      property type : String?

      def initialize(@name, @nesting, @superclass, @path)
      end
    end

    @units = {} of String => Array(Unit)
    @by_last_segment = {} of String => Array(String)

    def analyze
      parsed = ordered_scan_files(get_files_by_extension(".rb")) do |path|
        next if ruby_non_production_path?(path)
        content = ruby_source(path)
        next unless content_matches?(content, FILE_GATE_RE)
        parse_file(path, content)
      end

      mount = nil.as(String?)
      parsed.each do |units, file_mount|
        units.each { |unit| (@units[unit.name] ||= [] of Unit) << unit }
        mount ||= file_mount
      end
      @units.each_key { |name| (@by_last_segment[name.split("::").last] ||= [] of String) << name }
      # ponytail: one mount per scan; per-schema mounts if a repo serves several.
      mount = mount ? "/#{mount.lstrip('/')}" : Specification::GraphqlSdlParser::DEFAULT_GRAPHQL_PATH

      seen = Set(String).new
      root_types.each do |kind, type_name|
        fields_of(type_name, Set(String).new).each do |field, owner|
          endpoint = build_endpoint(field, owner, kind, type_name, mount)
          @result << endpoint if seen.add?(endpoint.url)
        end
      end
      @result
    end

    # {root kind, qualified class name} from every `< GraphQL::Schema` class,
    # or from conventionally named root classes when no schema class exists.
    private def root_types : Array(Tuple(String, String))
      roots = [] of Tuple(String, String)
      @units.each_value do |units|
        units.each do |unit|
          next unless unit.superclass.try(&.lchop("::")) == "GraphQL::Schema"
          unit.roots.each do |kind, ref|
            resolve(ref, unit.nesting).try { |name| roots << {kind, name} }
          end
        end
      end
      return roots.uniq unless roots.empty?

      @units.each do |name, units|
        kind = FALLBACK_ROOTS[name.split("::").last]?
        roots << {kind, name} if kind && units.any? { |unit| !unit.fields.empty? || !unit.includes.empty? }
      end
      roots
    end

    private def parse_file(path : String, content : String) : Tuple(Array(Unit), String?)?
      units = [] of Unit
      stack = [] of Tuple(Unit, Int32)
      field_block = nil.as(Tuple(Array(Arg), Int32)?)
      lines = content.lines
      i = 0
      while i < lines.size
        line = Noir::RubyCalleeExtractor.strip_comment(lines[i], preserve_strings: true)
        indent = line.size - line.lstrip.size

        if line.matches?(END_RE)
          if (block = field_block) && indent <= block[1]
            field_block = nil
          elsif (top = stack.last?) && indent <= top[1]
            stack.pop
          end
        elsif m = line.match(CLASS_RE)
          parent = stack.last?.try(&.[0])
          raw = m[1]
          name = raw.starts_with?("::") || parent.nil? ? raw.lchop("::") : "#{parent.name}::#{raw}"
          unit = Unit.new(name, [name] + (parent.try(&.nesting) || [] of String), m[2]?, path)
          units << unit
          stack << {unit, indent} unless line.matches?(ONE_LINE_END_RE)
        elsif top = stack.last?.try(&.[0])
          if line.matches?(FIELD_RE)
            stmt, i = statement(lines, i)
            if field = parse_field(stmt, path, i + 1 - stmt.count('\n'))
              top.fields << field
              field_block = {field.args, indent} if stmt.matches?(DO_TAIL_RE)
            end
          elsif line.matches?(ARGUMENT_RE)
            stmt, i = statement(lines, i)
            if arg = parse_argument(stmt)
              (field_block.try(&.[0]) || top.args) << arg
            end
          elsif m = line.match(INCLUDE_RE)
            top.includes << {m[1], i + 1}
          elsif m = line.match(GRAPHQL_NAME_RE)
            top.graphql_name = m[1]
          elsif m = line.match(ROOT_RE)
            top.roots[ROOT_KINDS[m[1]]] = m[2]
          elsif m = line.match(TYPE_DECL_RE)
            top.type ||= split_call(m[1]).first?
          end
        end
        i += 1
      end

      mount = content.includes?("graphql#") ? content.match(MOUNT_RE).try(&.[1]) : nil
      return if units.empty? && mount.nil?
      {units, mount}
    end

    # The statement starting at `start`, joined across continuation lines
    # (a trailing comma or an unclosed paren/bracket), and the index of its
    # last line.
    private def statement(lines : Array(String), start : Int32) : Tuple(String, Int32)
      stmt = Noir::RubyCalleeExtractor.strip_comment(lines[start], preserve_strings: true).rstrip
      i = start
      # ponytail: paren/bracket counting ignores string contents; the 20-line
      # cap bounds the damage of a stray `(` inside a description.
      while i + 1 < lines.size && i - start < 20 && (stmt.ends_with?(',') || stmt.ends_with?('\\') ||
            stmt.count('(') > stmt.count(')') || stmt.count('[') > stmt.count(']'))
        i += 1
        stmt = "#{stmt.rchop('\\')}\n#{Noir::RubyCalleeExtractor.strip_comment(lines[i], preserve_strings: true).rstrip}"
      end
      {stmt, i}
    end

    # `field :name, Type, "desc", null: false, camelize: false, resolver: R`
    private def parse_field(stmt : String, path : String, line : Int32) : Field?
      name, positional, kwargs = parse_call(stmt) || return
      resolver = kwargs["resolver"]? || kwargs["mutation"]? || kwargs["subscription"]?
      type_expr = kwargs["type"]? || positional.first?
      # With a resolver, a string second positional is the description.
      type_expr = nil if resolver && type_expr && type_expr.starts_with?('"')
      type = type_expr ? graphql_type(type_expr, kwargs["null"]? == "false") : ""
      connection = kwargs["connection"]?.try(&.==("true"))
      Field.new(wire_name(name, kwargs), type, [] of Arg, resolver, connection, path, line)
    end

    # `argument :id, ID, required: false, camelize: false`
    private def parse_argument(stmt : String) : Arg?
      name, positional, kwargs = parse_call(stmt) || return
      type_expr = kwargs["type"]? || positional.first? || return
      required = kwargs["required"]?
      {name: wire_name(name, kwargs), type: graphql_type(type_expr, required.nil? || required == "true")}
    end

    # Name, positional arguments and keyword arguments of a `field` /
    # `argument` call.
    private def parse_call(stmt : String) : Tuple(String, Array(String), Hash(String, String))?
      head = stmt.match(CALL_HEAD_RE) || return
      body = head.post_match.sub(DO_TAIL_RE, "").strip
      body = body.rchop(')') if head[1]?
      parts = split_call(body)
      name_m = parts.first?.try(&.match(SYMBOL_NAME_RE)) || return
      positional = [] of String
      kwargs = {} of String => String
      parts.skip(1).each do |part|
        if m = part.match(KWARG_RE)
          kwargs[m[1]] = m[2].strip
        else
          positional << part
        end
      end
      {name_m[1]? || name_m[2], positional, kwargs}
    end

    private def split_call(text : String) : Array(String)
      Noir::TopLevelSplit.split(text, ',', Noir::TopLevelSplit::Rules.new)
    end

    private def wire_name(name : String, kwargs : Hash(String, String)) : String
      kwargs["camelize"]? == "false" ? name : camelize(name)
    end

    # graphql-ruby's `Member::BuildType.camelize`: `user_ID` → `userId`,
    # `_secret_key` → `_secretKey`.
    private def camelize(name : String) : String
      return name if name == "_" || !name.includes?('_')
      camelized = name.split('_').join(&.capitalize)
      camelized = camelized.sub(0, camelized[0].downcase) unless camelized.empty?
      "#{"_" * (name.size - name.lstrip('_').size)}#{camelized}"
    end

    # Ruby type expression → GraphQL type string: `[Types::PostType]` →
    # `[Post!]`, `String` + required → `String!`.
    private def graphql_type(expr : String, non_null : Bool) : String
      expr = expr.strip
      type = if expr.starts_with?('[') && expr.ends_with?(']')
               inner = split_call(expr[1...-1])
               element_null = inner.skip(1).any?(&.matches?(NULL_TRUE_RE))
               "[#{graphql_type(inner.first? || "", !element_null)}]"
             else
               graphql_name_of(expr)
             end
      non_null ? "#{type}!" : type
    end

    private def graphql_name_of(expr : String) : String
      expr = expr.strip.delete('"').delete('\'')
      return "#{graphql_name_of(expr.rchop(".connection_type"))}Connection" if expr.ends_with?(".connection_type")
      last = expr.split("::").last
      SCALAR_ALIASES[last]? || default_graphql_name(last)
    end

    # graphql-ruby's `default_graphql_name`: the class name minus a `Type`
    # suffix.
    private def default_graphql_name(class_name : String) : String
      last = class_name.split("::").last
      last.ends_with?("Type") && last != "Type" ? last.rchop("Type") : last
    end

    private def graphql_name_for(name : String) : String
      @units[name]?.try &.each { |unit| unit.graphql_name.try { |gname| return gname } }
      default_graphql_name(name)
    end

    # Fields of `name`, its included modules and its superclasses, each with
    # the unit that declared it (for resolving its `resolver:` reference).
    private def fields_of(name : String, visited : Set(String)) : Array(Tuple(Field, Unit))
      result = [] of Tuple(Field, Unit)
      return result unless visited.add?(name)
      (@units[name]? || [] of Unit).each do |unit|
        unit.fields.each { |field| result << {field, unit} }
        unit.includes.each do |ref, line|
          if node = RELAY_NODE_FIELDS[ref.split("::").last]?
            result << {Field.new(node[0], node[2], node[1], nil, false, unit.path, line), unit}
          elsif included = resolve(ref, unit.nesting)
            result.concat(fields_of(included, visited))
          end
        end
        parent_of(unit).try { |parent| result.concat(fields_of(parent, visited)) }
      end
      result
    end

    # Every unit of `name` and of its superclasses, nearest first.
    private def ancestors(name : String, visited = Set(String).new) : Array(Unit)
      return [] of Unit unless visited.add?(name)
      (@units[name]? || [] of Unit).flat_map do |unit|
        parent = parent_of(unit)
        [unit] + (parent ? ancestors(parent, visited) : [] of Unit)
      end
    end

    # Arguments a resolver/mutation class declares, superclasses included.
    private def args_of(name : String) : Array(Arg)
      ancestors(name).flat_map(&.args)
    end

    private def relay_classic?(name : String) : Bool
      ancestors(name).any?(&.superclass.try(&.ends_with?("RelayClassicMutation")))
    end

    # A resolver's `type Types::PostType, null: false`, superclasses included.
    private def resolver_type(name : String) : String?
      ancestors(name).each { |unit| unit.type.try { |type| return graphql_type(type, false) } }
      nil
    end

    private def parent_of(unit : Unit) : String?
      unit.superclass.try { |ref| resolve(ref, unit.nesting) }
    end

    # Ruby constant lookup, approximated: the lexical nesting first, then the
    # top level, then any class whose qualified name ends with `ref` (Rails
    # autoloading makes `Types::Foo` reachable from anywhere).
    private def resolve(ref : String, nesting : Array(String)) : String?
      ref = ref.lchop("::")
      nesting.each do |scope|
        candidate = "#{scope}::#{ref}"
        return candidate if @units.has_key?(candidate)
      end
      return ref if @units.has_key?(ref)
      suffix = "::#{ref}"
      @by_last_segment[ref.split("::").last]?.try &.find(&.ends_with?(suffix))
    end

    private def build_endpoint(field : Field, owner : Unit, kind : String, root : String, mount : String) : Endpoint
      args = field.args.dup
      return_type = field.type
      if (ref = field.resolver) && (resolver = resolve(ref, owner.nesting))
        if relay_classic?(resolver)
          # RelayClassicMutation wraps its arguments in one `input` object.
          gname = graphql_name_for(resolver)
          args.unshift({name: "input", type: "#{gname}Input!"})
          return_type = "#{gname}Payload" if return_type.empty?
        else
          args = args_of(resolver) + args
          return_type = resolver_type(resolver) || "" if return_type.empty?
        end
      end
      connection = field.connection
      if connection.nil?
        base = return_type.delete("[]!")
        connection = base.ends_with?("Connection") && base != "Connection"
      end
      args.concat(CONNECTION_ARGS) if connection

      Specification::GraphqlSdlParser.field_endpoint(field.path, field.line, kind, field.name, args.uniq(&.[:name]),
        return_type, TAG_SOURCE, mount, graphql_name_for(root))
    end
  end
end
