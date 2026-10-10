require "../../../models/analyzer"
require "./common"
require "../../../minilexers/csharp_lexer"
require "../specification/graphql_sdl_parser"

module Analyzer::CSharp
  # HotChocolate (https://chillicream.com/docs/hotchocolate) code-first
  # schemas: every root (Query/Mutation/Subscription) field becomes one
  # endpoint in the same shape the SDL analyzer emits.
  #
  # A class is a root when it carries `[QueryType]`/`[MutationType]`/
  # `[SubscriptionType]` (source generator; several classes merge into one
  # root), `[ExtendObjectType(...)]` naming a root, or is registered with
  # `AddQueryType<T>()` and friends. A registered `ObjectType<T>` descriptor
  # class contributes `T`'s members plus its literal `descriptor.Field("x")`
  # fields. Wiring (`Program.cs`) and root classes live in different files,
  # so the analyzer collects across every `.cs` file first, then resolves.
  #
  # Field/argument names follow HotChocolate's `NameFormattingHelpers`:
  # `[GraphQLName]` wins, otherwise a method loses its `Get` prefix (and its
  # `Async` suffix when it returns a task/stream) and the leading uppercase
  # run is lowered.
  class HotChocolate < Analyzer
    analyzer_for "cs_hotchocolate"

    include Common

    alias Arg = NamedTuple(name: String, type: String)

    ROOT_KINDS = %w[Query Mutation Subscription]
    # `AddQueryType<Query>()`, `.AddMutationType<Mutations.Mutation>()`, and the
    # pre-v11 `RegisterQueryType<QueryType>()`.
    ADD_ROOT = /\b(?:Add|Register)(Query|Mutation|Subscription)Type\s*<\s*([\w.]+)\s*>/
    # `app.MapGraphQL()` / `app.MapGraphQL("/api/graphql")` (HC 11+), and the
    # older `app.UseGraphQL("/graphql")` middleware.
    MOUNT        = /\b(?:MapGraphQL(?:Http)?|UseGraphQL)\s*\(\s*(?:path\s*:\s*)?@?"([^"]+)"/
    MUTATION_CON = /\bAddMutationConventions\s*\(([^)]*)\)/
    # Relay `node(id:)` / `nodes(ids:)` query fields.
    GLOBAL_ID   = /\bAddGlobalObjectIdentification\s*\(/
    WIRING_GATE = /\b(?:Add|Register)(?:Query|Mutation|Subscription)Type\b|\bMapGraphQL|\bUseGraphQL\b|\bAddMutationConventions\b|\bAddGlobalObjectIdentification\b/
    # `[Subscribe(With = nameof(SubscribeToX))]`: the stream method is not a field.
    SUBSCRIBE_WITH = /\bSubscribe\s*\(\s*With\s*=\s*(?:nameof\s*\(\s*(\w+)\s*\)|"(\w+)")/

    # Files worth lexing for root classes, besides those naming a registered type.
    CLASS_GATE = /\b(?:Query|Mutation|Subscription)Type\b|\bExtendObjectType\b|\bObjectType\s*<|\[\s*(?:Query|Mutation|Subscription)\s*[\](,]/

    CLASS_DECL = /\bclass\s+(\w+)(?:\s*<[^>]*>)?\s*(?::\s*([^{]*))?/
    # `[QueryType]`, `[HotChocolate.Types.MutationType]`, `[QueryType, Foo]`.
    ROOT_ATTR = /(?:\[|,)\s*(?:[\w.]+\.)?(Query|Mutation|Subscription)Type(?:Attribute)?\s*[\](,]/
    # HC 14+ source generator: `[Query] public static Book GetBook()` in any
    # static class adds that one member to the root.
    MEMBER_ROOT_ATTR = /(?:\[|,)\s*(?:[\w.]+\.)?(Query|Mutation|Subscription)(?:Attribute)?\s*[\](,]/
    # `[ExtendObjectType("Query")]`, `(Name = "Query")`, `(typeof(Query))`,
    # `(OperationTypeNames.Query)`, `[ExtendObjectType<Query>]`.
    EXTEND_ATTR    = /\bExtendObjectType\s*(?:<\s*(?:[\w.]+\.)?(\w+)\s*>|\(\s*(?:Name\s*=\s*)?(?:typeof\s*\(\s*(?:[\w.]+\.)?(\w+)\s*\)|"(\w+)"|(?:[\w.]+\.)?OperationTypeNames\.(\w+)))/
    OBJECT_TYPE_OF = /\A\s*(?:[\w.]+\.)?ObjectType\s*(?:<\s*(?:[\w.]+\.)?(\w+)\s*>)?\s*(?:,|\z)/

    # A public member: `public static async Task<Book> GetBookAsync(` or
    # `public string Name { get; }` / `public string Hello => "x";`.
    MEMBER        = /\A\s*public\s+((?:(?:static|async|virtual|override|sealed|new|partial|required|readonly|unsafe|extern)\s+)*)([\w<>\[\],.?\s]+?)\s+@?(\w+)\s*(\(|<|\{|=>)/
    LEADING_ATTRS = /\A\s*(?:\[(?:[^\[\]"]|"[^"]*")+\]\s*)+/
    ATTRIBUTE     = /\[(?:[^\[\]"]|"[^"]*")+\]/
    GRAPHQL_NAME  = /\bGraphQLName\s*\(\s*@?"([^"]+)"/

    # Members HotChocolate never binds (`DefaultTypeInspector.CanBeHandled`)
    # or that source generators claim (`[DataLoader]`).
    SKIP_MEMBER_ATTR = /\b(?:GraphQLIgnore|DataLoader)\b/
    SYSTEM_MEMBERS   = Set{"ToString", "GetHashCode", "Equals", "CompareTo", "Clone", "GetType"}
    NON_MEMBER_TYPES = Set{"class", "record", "struct", "interface", "enum", "delegate", "event", "const"}
    NO_FIELD_RETURNS = Set{"void", "Task", "ValueTask", "object", "Task<object>", "ValueTask<object>"}

    # Parameters HotChocolate resolves itself instead of exposing as
    # arguments (`Resolvers/Expressions/Parameters/*ParameterExpressionBuilder`).
    # Registered services are inferred without an attribute, so the shared
    # DI-type heuristic covers `ApplicationDbContext`, `IBookService`, ….
    INJECTED_ATTR  = /\b(?:Service|Parent|EventMessage|GlobalState|ScopedState|LocalState|IsSelected|FromServices|FromKeyedServices|ScopedService)\b/
    INJECTED_TYPES = Set{
      "CancellationToken", "ClaimsPrincipal", "DocumentNode", "OperationDefinitionNode",
      "Operation", "Selection", "Path", "ConnectionFlags", "ObjectType", "ObjectField",
      "Schema", "SetState",
    }

    SCALARS = {
      "string" => "String", "String" => "String", "char" => "String",
      "int" => "Int", "Int32" => "Int", "short" => "Short", "Int16" => "Short",
      "byte" => "Byte", "long" => "Long", "Int64" => "Long",
      "bool" => "Boolean", "Boolean" => "Boolean",
      "float" => "Float", "double" => "Float", "Single" => "Float", "Double" => "Float",
      "decimal" => "Decimal", "Guid" => "UUID", "Uri" => "URL",
      "DateTime" => "DateTime", "DateTimeOffset" => "DateTime", "DateOnly" => "Date",
      "TimeSpan" => "TimeSpan", "object" => "Any",
    }
    LIST_TYPES = Set{
      "IEnumerable", "IQueryable", "IAsyncEnumerable", "IExecutable", "List", "IList",
      "IReadOnlyList", "ICollection", "IReadOnlyCollection", "HashSet", "ISet",
      "ImmutableArray", "ImmutableList",
    }

    private record Member,
      cs_name : String,
      name : String,
      line : Int32,
      args : Array(Arg),
      return_type : String,
      mutation_convention : Bool,
      kind : String?

    private class ClassInfo
      property members = [] of Member
      property literal_fields = [] of Member
      property explicit_names : Set(String)? = nil
      property ignored_names = Set(String).new
      getter name, path, line, attr_kind, extend_target, object_type_of, descriptor, static_members

      def initialize(@name : String, @path : String, @line : Int32, @attr_kind : String?, @extend_target : String?,
                     @object_type_of : String?, @descriptor : Bool, @static_members : Bool)
      end
    end

    def analyze
      files = get_files_by_extension(".cs").reject do |path|
        Common.csharp_test_path?(base_relative_path(path)) || !File.exists?(path)
      end

      registered = {} of String => String # class name => root kind
      mount = nil
      conventions = false
      node = nil
      files.each do |path|
        content = read_file_content(path)
        next unless content_matches?(content, WIRING_GATE)
        content.scan(ADD_ROOT) { |m| registered[m[2].split('.').last] = m[1] }
        mount ||= content.match(MOUNT).try(&.[1])
        content.scan(MUTATION_CON) { |m| conventions ||= !m[1].includes?("false") }
        if node.nil? && (gm = content.match(GLOBAL_ID))
          node = {path, content[0...gm.begin(0)].count('\n') + 1}
        end
      rescue e
        logger.debug "Error scanning HotChocolate wiring in #{path}: #{e}"
      end

      classes = {} of String => Array(ClassInfo)
      collect(files, registered.keys.to_set, true, classes)
      # Descriptor-first `QueryType : ObjectType<Query>` binds `Query`'s
      # members, a class nothing else names, so it takes a second pass.
      runtime = classes.values.flat_map(&.compact_map(&.object_type_of)).to_set - classes.keys.to_set
      collect(files, runtime, false, classes) unless runtime.empty?

      mount ||= "/graphql"
      emit(classes, registered, mount, conventions)
      if node
        @result << Specification::GraphqlSdlParser.field_endpoint(node[0], node[1], "Query", "node",
          [{name: "id", type: "ID!"}], "Node", "cs_hotchocolate_analyzer", mount)
        @result << Specification::GraphqlSdlParser.field_endpoint(node[0], node[1], "Query", "nodes",
          [{name: "ids", type: "[ID!]!"}], "[Node]!", "cs_hotchocolate_analyzer", mount)
      end
      @result
    end

    # `markers` also records attribute-marked classes (first pass); without
    # it only the classes named in `names` are recorded.
    private def collect(files : Array(String), names : Set(String), markers : Bool,
                        classes : Hash(String, Array(ClassInfo)))
      names_re = names.empty? ? nil : Regex.union(names.map { |n| /\b#{Regex.escape(n)}\b/ })
      files.each do |path|
        content = read_file_content(path)
        next unless content.includes?("class")
        next unless (markers && content_matches?(content, CLASS_GATE)) ||
                    (names_re && content_matches?(content, names_re))
        collect_file(content, path, names, markers, classes)
      rescue e
        logger.debug "Error analyzing HotChocolate types in #{path}: #{e}"
      end
    end

    private record Frame, info : ClassInfo?, body_depth : Int32, body : String::Builder?

    # One linear walk over the masked lines: a stack of open classes, the
    # pending attribute text, and members read only at a root class's own
    # body depth (nested blocks and types never leak fields).
    private def collect_file(content : String, path : String, names : Set(String), markers : Bool,
                             classes : Hash(String, Array(ClassInfo)))
      # Comments blanked in both views: after `[GraphQLName("x")] // note`
      # the comment read as the declaration and the attribute was dropped.
      lexer = Noir::CSharpLexer.new(content)
      lines = lexer.code_lines
      masked = lexer.masked_lines
      frames = [] of Frame
      opened = [] of Bool
      attrs = ""
      attr_depth = 0
      depth = 0
      i = 0

      while i < lines.size
        raw = lines[i]
        m = masked[i]? || raw
        start_depth = depth
        last_line = i
        frame = frames.last?
        frame.try(&.body).try { |io| io << raw << '\n' }
        attr_line = m.lstrip.starts_with?('[')
        am = attr_line ? LEADING_ATTRS.match(raw) : nil
        pushed = false

        if attr_depth > 0
          attrs += raw
          attr_depth += m.count('[') - m.count(']')
        elsif attr_line && am.nil?
          # A multi-line attribute (`[UsePaging(\n IncludeTotalCount = true)]`).
          attrs += raw
          attr_depth = m.count('[') - m.count(']')
        elsif !m.blank?
          decl = raw
          if am
            attrs += am[0]
            decl = am.post_match
          end
          unless decl.blank?
            if m.includes?("class") && (cm = CLASS_DECL.match(class_header(decl, lines, masked, i)))
              info = class_info(cm, decl, attrs, path, i + 1, names, markers)
              classes.put_if_absent(info.name) { [] of ClassInfo } << info if info
              body = info && info.descriptor ? String::Builder.new : nil
              frames << Frame.new(info, start_depth + 1, body)
              opened << false
              pushed = true
            elsif frame && (info = frame.info) && start_depth == frame.body_depth &&
                  !info.descriptor && (mm = MEMBER.match(decl))
              member, last_line = parse_member(mm, attrs, lines, masked, i, info.static_members)
              info.members << member if member
              attrs.match(SUBSCRIBE_WITH).try { |sw| info.ignored_names << (sw[1]? || sw[2]) }
            end
            attrs = ""
          end
        end

        (i..last_line).each do |j|
          depth += (masked[j]? || lines[j]).count('{') - (masked[j]? || lines[j]).count('}')
        end
        # A class is open once its `{` appears, even when the body closes on
        # the same line (`class Empty { }`).
        frames.each_index { |k| opened[k] ||= depth >= frames[k].body_depth }
        opened[-1] ||= m.includes?('{') if pushed
        while (top = frames.last?) && opened.last && depth < top.body_depth
          frames.pop
          opened.pop
          if (info = top.info) && (io = top.body)
            read_descriptor(info, io.to_s)
          end
        end
        i = last_line + 1
      end
    end

    # The declaration plus the lines up to its `{`: the base list often sits
    # on its own line (`class QueryType\n    : ObjectType<Query>`).
    private def class_header(decl : String, lines : Array(String), masked : Array(String), index : Int32) : String
      header = decl
      k = index
      while !(masked[k]? || "").includes?('{') && k < index + 4 && k + 1 < lines.size
        k += 1
        header += " " + lines[k]
      end
      header
    end

    private def class_info(cm : Regex::MatchData, decl : String, attrs : String, path : String,
                           line : Int32, names : Set(String), markers : Bool) : ClassInfo?
      name = cm[1]
      attr_kind = markers ? attrs.match(ROOT_ATTR).try(&.[1]) : nil
      extend_target = markers ? attrs.match(EXTEND_ATTR).try { |em| em[1]? || em[2]? || em[3]? || em[4]? } : nil
      static_class = decl.matches?(/\bstatic\s+(?:partial\s+)?class\b/)
      return unless attr_kind || extend_target || names.includes?(name) || (markers && static_class)

      object_type = (cm[2]? || "").match(OBJECT_TYPE_OF)
      ClassInfo.new(name, path, line, attr_kind, extend_target, object_type.try(&.[1]?), !object_type.nil?,
        static_class || !attr_kind.nil?)
    end

    # `descriptor.Field("name")` literal fields (with `.Argument("x", …)`),
    # plus the explicit-binding and `Ignore(f => f.X)` filters on the runtime
    # type's members.
    # ponytail: `.Name("x")` renames and argument types are not read; a
    # lambda-bound field keeps its member-derived name, literal arguments are typed String.
    private def read_descriptor(info : ClassInfo, body : String)
      body.scan(/\.Field\s*\(\s*@?"(\w+)"/) do |lm|
        start = lm.end(0)
        chunk = body[start...(body.index(".Field", start) || body.size)]
        args = chunk.scan(/\.Argument\s*\(\s*@?"(\w+)"/).map { |a| {name: a[1], type: "String"} }
        line = info.line + 1 + body[0...lm.begin(0)].count('\n')
        info.literal_fields << Member.new(lm[1], lm[1], line, args, "", false, nil)
      end
      if body.matches?(/\bBindFieldsExplicitly\b|\bBindingBehavior\.Explicit\b/)
        info.explicit_names = body.scan(/\.Field\s*\(\s*\w+\s*=>\s*\w+\.(\w+)/).map(&.[1]).to_set
      end
      body.scan(/\.Ignore\s*\(\s*\w+\s*=>\s*\w+\.(\w+)/) { |im| info.ignored_names << im[1] }
    end

    # Returns the member (nil when HotChocolate would not bind it) and the
    # last line its declaration spans.
    private def parse_member(mm : Regex::MatchData, attrs : String, lines : Array(String),
                             masked : Array(String), index : Int32, static_members : Bool) : Tuple(Member?, Int32)
      modifiers, type, cs_name, opener = mm[1], mm[2].strip, mm[3], mm[4]
      return {nil, index} if opener == "<" # generic method definition
      return {nil, index} if NON_MEMBER_TYPES.includes?(type.split.first) || type.includes?("operator")
      return {nil, index} if modifiers.includes?("static") && !static_members
      return {nil, index} if NO_FIELD_RETURNS.includes?(type.gsub(/\s+/, ""))
      return {nil, index} if SYSTEM_MEMBERS.includes?(cs_name) || attrs.matches?(SKIP_MEMBER_ATTR)

      last = index
      args = [] of Arg
      method = opener == "("
      if method
        signature, last = build_signature(lines, masked, index)
        if list = extract_balanced_param_list(signature)
          split_csharp_parameters(list).each do |decl|
            return {nil, last} if decl.matches?(/\A\s*(?:\[[^\]]*\]\s*)*(?:ref|out)\s/)
            arg = parse_argument(decl)
            args << arg if arg
          end
        end
      end

      name = attrs.match(GRAPHQL_NAME).try(&.[1]) || field_name(cs_name, method, type)
      args[0] = {name: args[0][:name], type: "ID!"} if !args.empty? && attrs.includes?("NodeResolver")
      args.concat(middleware_args(attrs, type))
      member = Member.new(cs_name, name, index + 1, args, graphql_type(type),
        attrs.matches?(/\bUseMutationConvention\b/), attrs.match(MEMBER_ROOT_ATTR).try(&.[1]))
      {member, last}
    end

    private def parse_argument(decl : String) : Arg?
      attrs = decl.scan(ATTRIBUTE).join(" ", &.[0])
      return if attrs.matches?(INJECTED_ATTR)
      body = decl.gsub(ATTRIBUTE, " ").split('=').first.strip
      body = body.sub(/\A(?:params|in|this|scoped)\s+/, "")
      dm = body.match(/\A(.+?)\s+@?(\w+)\z/m)
      return unless dm
      type = dm[1].strip
      base = type.rchop('?').gsub(/<.*>/m, "").split('.').last
      # `IFile` is the Upload scalar: an interface, but sent by the client.
      return if INJECTED_TYPES.includes?(base) || base.ends_with?("DataLoader") ||
                (base != "IFile" && Common.csharp_service_type?(type))

      name = attrs.match(GRAPHQL_NAME).try(&.[1]) || format_field_name(dm[2])
      gtype = attrs.matches?(/(?:\[|,)\s*ID\b/) ? graphql_type(type).gsub(/\b(?!ID\b)\w+\b/, "ID") : graphql_type(type)
      {name: name, type: gtype}
    end

    # Arguments added by the data middleware attributes.
    private def middleware_args(attrs : String, return_type : String) : Array(Arg)
      args = [] of Arg
      return args unless attrs.includes?("Use")
      elem = graphql_type(return_type).delete("[]!")
      if attrs.matches?(/\bUsePaging\b/)
        args.concat([{name: "first", type: "Int"}, {name: "after", type: "String"},
                     {name: "last", type: "Int"}, {name: "before", type: "String"}])
      end
      args.concat([{name: "skip", type: "Int"}, {name: "take", type: "Int"}]) if attrs.matches?(/\bUseOffsetPaging\b/)
      args << {name: "where", type: "#{elem}FilterInput"} if attrs.matches?(/\bUseFiltering\b/)
      args << {name: "order", type: "[#{elem}SortInput!]"} if attrs.matches?(/\bUseSorting\b/)
      args
    end

    # `NameFormattingHelpers.FormatMethodName`: drop `Get`, drop `Async` only
    # when the method returns a task/stream, then `FormatFieldName`.
    private def field_name(cs_name : String, method : Bool, return_type : String) : String
      name = cs_name
      if method
        name = name[3..] if name.starts_with?("Get") && name.size > 3
        if name.ends_with?("Async") && name.size > 5 &&
           return_type.matches?(/\A(?:[\w.]+\.)?(?:Task|ValueTask|IAsyncEnumerable)\s*</)
          name = name[0...-5]
        end
      end
      format_field_name(name)
    end

    # `NameFormattingHelpers.FormatFieldName`: lower the leading uppercase
    # run, re-raising its last letter when a letter follows (`FOOBar` → `fooBar`).
    private def format_field_name(name : String) : String
      chars = name.chars
      return name if chars.empty? || chars[0].lowercase?
      p = 0
      while p < chars.size && chars[p].letter? && chars[p].uppercase?
        chars[p] = chars[p].downcase
        p += 1
      end
      chars[p - 1] = chars[p - 1].upcase if p < chars.size && p > 1 && chars[p].letter?
      chars.join
    end

    # Best-effort C# → GraphQL type string (nullable reference types assumed
    # on, as in the .NET templates). Used for the operation document only.
    private def graphql_type(cs : String) : String
      t = cs.gsub(/\s+/, "")
      nullable = t.ends_with?('?')
      t = t.rchop('?')
      bang = nullable ? "" : "!"
      return "[#{graphql_type(t[0...-2])}]#{bang}" if t.ends_with?("[]")

      if gm = t.match(/\A(?:[\w.]+\.)?(\w+)<(.+)>\z/)
        generic, inner = gm[1], gm[2]
        case generic
        when "Task", "ValueTask"    then return graphql_type(inner)
        when "Nullable", "Optional" then return graphql_type(inner).rchop('!')
        when .in?(LIST_TYPES)       then return "[#{graphql_type(inner)}]#{bang}"
        end
        return "#{generic}#{bang}"
      end
      base = t.split('.').last
      "#{SCALARS[base]? || base}#{bang}"
    end

    private def emit(classes : Hash(String, Array(ClassInfo)), registered : Hash(String, String),
                     mount : String, conventions : Bool)
      # ponytail: one schema per scan — roots, mount path and conventions are
      # pooled across every project and named schemas (`AddGraphQLServer("x")`);
      # scope them by `.csproj` root (Common.project_roots) if multi-schema repos matter.
      seen = Set(Tuple(String, String)).new
      classes.each_value do |infos|
        infos.each do |info|
          target = info.extend_target
          root_kind = info.attr_kind || (target && (registered[target]? || (ROOT_KINDS.includes?(target) ? target : nil))) ||
                      registered[info.name]?

          own = info.descriptor ? info.literal_fields : info.members.reject { |m| info.ignored_names.includes?(m.cs_name) }
          members = own.map { |m| {m, info.path} }
          if info.descriptor && (runtime = info.object_type_of)
            explicit = info.explicit_names
            (classes[runtime]? || [] of ClassInfo).each do |rt|
              rt.members.each do |rm|
                next if explicit && !explicit.includes?(rm.cs_name)
                members << {rm, rt.path} unless info.ignored_names.includes?(rm.cs_name)
              end
            end
          end

          members.each do |member, path|
            next unless (kind = member.kind || root_kind) && seen.add?({kind, member.name})
            args = member.args
            if kind == "Mutation" && (conventions || member.mutation_convention) && !args.empty?
              input = "#{member.name[0].upcase}#{member.name[1..]}Input"
              args = [{name: "input", type: "#{input}!"}] unless args.any? { |a| a[:type].rchop('!') == input }
            end
            @result << Specification::GraphqlSdlParser.field_endpoint(path, member.line, kind, member.name,
              args, member.return_type, "cs_hotchocolate_analyzer", mount)
          end
        end
      end
    end
  end
end
