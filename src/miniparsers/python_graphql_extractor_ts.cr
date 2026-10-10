require "../ext/tree_sitter/tree_sitter"
require "../utils/top_level_split"

module Noir
  # Outline of the Python modules behind a code-first GraphQL schema
  # (Strawberry, Graphene): top-level classes with their bases, decorators
  # and members, module-level functions, imports and `Schema(...)` calls,
  # plus the cross-file name resolution that stitches root types together
  # from mixins in other modules. Library rules (which member is a field,
  # what its arguments are) stay with the analyzers; no file I/O here.
  module PythonGraphqlExtractor
    extend self

    # `Schema(...)` keyword => root operation type; also the positional order.
    ROOT_KINDS = {"query" => "Query", "mutation" => "Mutation", "subscription" => "Subscription"}

    record Param, name : String, type_hint : String?, default : String?

    # `params` is nil for a class attribute and set for a `def`.
    record Member, path : String, name : String, line : Int32, decorators : Array(String),
      type_hint : String?, value : String?, params : Array(Param)?, returns : String?

    record ClassDecl, path : String, name : String, line : Int32, bases : Array(String),
      decorators : Array(String), members : Array(Member), inner : Hash(String, ClassDecl)

    # A `Schema(...)` call. `camel` is false when the file opts out of the
    # library's default auto-camelCase.
    record SchemaCall, path : String, line : Int32, positional : Array(String),
      keywords : Hash(String, String), camel : Bool

    class FileOutline
      getter path : String
      getter classes = [] of ClassDecl
      getter functions = [] of Member
      # Local name => dotted target. A relative import's first segment is
      # the absolute directory it starts from.
      getter imports = {} of String => Array(String)
      getter schema_calls = [] of SchemaCall
      getter mounts = [] of String
      # Whether the file imports the library. Only those bind roots with a
      # `Schema(...)` call; the others are read for their classes.
      getter? library : Bool

      def initialize(@path, @library = true)
      end
    end

    # Every outline, indexed for `resolve`.
    class Index
      getter outlines : Array(FileOutline)
      getter classes = {} of String => Array(ClassDecl)
      getter functions = {} of String => Array(Member)
      @by_path = {} of String => FileOutline

      def initialize(@outlines)
        @outlines.each do |outline|
          @by_path[outline.path] = outline
          outline.classes.each { |c| (@classes[c.name] ||= [] of ClassDecl) << c }
          outline.functions.each { |f| (@functions[f.name] ||= [] of Member) << f }
        end
      end

      def outline(path : String) : FileOutline
        @by_path[path]
      end

      def library?(klass : ClassDecl) : Bool
        outline(klass.path).library?
      end

      # The one mount path every file agrees on, else nil.
      def mount_path : String?
        paths = @outlines.flat_map(&.mounts).uniq!
        paths.first if paths.size == 1
      end

      def resolve_class(from_path : String, ref : String, except : ClassDecl? = nil) : ClassDecl?
        PythonGraphqlExtractor.resolve(outline(from_path), ref, @classes, except)
      end

      def resolve_function(from_path : String, ref : String) : Member?
        PythonGraphqlExtractor.resolve(outline(from_path), ref, @functions, nil)
      end

      # Root kind, class and camelCase flag of every `Schema(query=...,
      # mutation=..., subscription=...)` binding. With none resolved, the
      # classes named Query / Mutation / Subscription that `accept` takes.
      def roots(& : ClassDecl -> Bool) : Array({String, ClassDecl, Bool})
        roots = [] of {String, ClassDecl, Bool}
        @outlines.each do |outline|
          outline.schema_calls.each do |call|
            ROOT_KINDS.each_with_index do |(keyword, kind), i|
              ref = call.keywords[keyword]? || call.positional[i]?
              next if ref.nil? || ref == "None"
              resolve_class(call.path, ref).try { |c| roots << {kind, c, call.camel} }
            end
          end
        end
        return roots unless roots.empty?
        ROOT_KINDS.each_value do |kind|
          @classes[kind]?.try &.each { |c| roots << {kind, c, true} if yield c }
        end
        roots
      end

      # Members of `klass` and its bases, a subclass's shadowing its base's.
      def members(klass : ClassDecl) : Array(Member)
        by_name = {} of String => Member
        lineage(klass).each { |c| c.members.each { |m| by_name[m.name] = m } }
        by_name.values
      end

      # `klass` and every base that resolves, bases first, each once.
      def lineage(klass : ClassDecl, seen = Set({String, Int32}).new) : Array(ClassDecl)
        return [] of ClassDecl unless seen.add?({klass.path, klass.line})
        chain = [] of ClassDecl
        klass.bases.reverse_each do |base|
          resolve_class(klass.path, base, klass).try { |b| chain.concat(lineage(b, seen)) }
        end
        chain << klass
      end
    end

    # `ref` as written in `outline`'s file (`Query`, `users.schema.Query`,
    # an import alias) to the declaration it names. Module paths are matched
    # as path suffixes, so absolute imports need no source-root guess.
    def resolve(outline : FileOutline, ref : String, index : Hash(String, Array(T)), except) : T? forall T
      parts = ref.strip.split('.')
      name = parts.last
      if target = outline.imports[parts.first]?
        parts = target + parts[1..]
        name = parts.last
      elsif parts.size == 1
        # Defined in the same file, but not the class being declared
        # (`class Query(Query)` names the imported one).
        local = index[name]?.try &.find { |c| c.path == outline.path && !same?(c, except) }
        return local if local
      end
      candidates = index[name]?.try(&.reject { |c| same?(c, except) }) || return
      if parts.size > 1
        mod = parts[0...-1].join('/')
        found = candidates.find { |c| module_stem(c.path).ends_with?(mod) && boundary?(module_stem(c.path), mod) } ||
                # Re-exported from a package `__init__` that lives above it.
                candidates.find { |c| module_stem(c.path).includes?("#{mod}/") }
        return found if found
      end
      # ponytail: a star import or an unresolvable module falls back to a
      # project-unique name; ambiguous names stay unresolved.
      candidates.first if candidates.size == 1
    end

    private def same?(decl, other) : Bool
      !other.nil? && decl.path == other.path && decl.line == other.line
    end

    private def module_stem(path : String) : String
      stem = path.rchop(".py")
      stem.ends_with?("/__init__") ? stem.rchop("/__init__") : stem
    end

    private def boundary?(stem : String, mod : String) : Bool
      stem.size == mod.size || mod.starts_with?('/') || stem[stem.size - mod.size - 1] == '/'
    end

    # Literal mount paths: Django/Flask `path("graphql/", GraphQLView...)`,
    # `add_url_rule`, FastAPI `include_router(router, prefix=...)` and ASGI
    # `add_route` / `mount` of a GraphQL app.
    URL_VIEW_MOUNT = /\b(?:path|re_path|url|add_url_rule)\(\s*r?(["'])\^?\/?([\w\-\/.]*?)\$?\1\s*,[^"']{0,120}?\b\w*GraphQLView\b/
    APP_VAR        = /^\s*(\w+)\s*(?::[^=\n]+)?=\s*(?:[\w.]+\.)?GraphQL(?:Router|App)?\(/m
    INCLUDE_ROUTER = /\binclude_router\(\s*(\w+)\s*,[^)]*?\bprefix\s*=\s*(["'])([^"'\n]*)\2/
    ROUTE_MOUNT    = /\.(?:add_route|add_websocket_route|mount)\(\s*(["'])([^"'\n]+)\1\s*,\s*((?:[\w.]+\.)?GraphQL(?:App)?\(|\w+\b)/
    CAMEL_OPT_OUT  = /\bauto_camel_?case\s*=\s*False\b/

    private def extract(path : String, source : String, library : Bool = true) : FileOutline
      outline = FileOutline.new(path, library)
      TreeSitter.parse_python(source) do |root|
        TreeSitter.each_named_child(root) { |node| top_level(node, source, outline) }
        next unless library
        camel = !source.matches?(CAMEL_OPT_OUT)
        TreeSitter.walk(root) do |node|
          next unless TreeSitter.node_type(node) == "call"
          callee = TreeSitter.field(node, "function").try { |f| TreeSitter.node_text(f, source) } || next
          next unless callee == "Schema" || callee.ends_with?(".Schema")
          positional, keywords = call_args(TreeSitter.node_text(node, source)) || next
          outline.schema_calls << SchemaCall.new(path, TreeSitter.node_start_row(node) + 1, positional, keywords, camel)
        end
      end
      read_mounts(source, outline.mounts) if source.includes?("GraphQL")
      outline
    end

    ROOT_CLASS = /^class\s+(?:Query|Mutation|Subscription)\b/m

    # What an analyzer needs from one file, or nil. A file importing the
    # library (`library`) gets a full outline. One that does not may still
    # compose the root types from other modules' mixins, or mount the
    # project's own `GraphQLView` subclass in `urls.py`: it is read for its
    # classes or its mount paths only.
    def outline(path : String, source : String, library : Bool) : FileOutline?
      return extract(path, source) if library
      if source.includes?("class ") && source.matches?(ROOT_CLASS)
        return extract(path, source, library: false)
      end
      return unless source.includes?("GraphQL")
      outline = FileOutline.new(path, library: false)
      read_mounts(source, outline.mounts)
      outline unless outline.mounts.empty?
    end

    private def read_mounts(source : String, mounts : Array(String))
      source.scan(URL_VIEW_MOUNT) { |m| mounts << "/#{m[2]}" }
      apps = source.scan(APP_VAR).map(&.[1])
      source.scan(INCLUDE_ROUTER) { |m| mounts << m[3] if apps.includes?(m[1]) && !m[3].empty? }
      source.scan(ROUTE_MOUNT) { |m| mounts << m[2] if m[3].ends_with?('(') || apps.includes?(m[3]) }
    end

    private def top_level(node : LibTreeSitter::TSNode, source : String, outline : FileOutline)
      case TreeSitter.node_type(node)
      when "import_statement", "import_from_statement"
        read_import(node, source, outline)
      when "class_definition", "decorated_definition", "function_definition"
        case decl = definition(node, source, outline.path)
        when ClassDecl then outline.classes << decl
        when Member    then outline.functions << decl
        end
      when "expression_statement"
        # Strawberry's `Query = merge_types("Query", (A, B))` is a root type
        # whose fields are its parts'.
        assignment = TreeSitter.first_named_child(node) || return
        return unless TreeSitter.node_type(assignment) == "assignment"
        left = TreeSitter.field(assignment, "left") || return
        right = TreeSitter.field(assignment, "right") || return
        positional, _ = call_args(TreeSitter.node_text(right, source)) || return
        callee = TreeSitter.field(right, "function").try { |f| TreeSitter.node_text(f, source) }
        return unless callee && (callee == "merge_types" || callee.ends_with?(".merge_types"))
        bases = positional[1]?.try { |t| TopLevelSplit.split(t.strip.lchop('(').lchop('[').rchop(')').rchop(']'), ',', TopLevelSplit::Rules::PYTHON) }
        bases = (bases || [] of String).map(&.strip).reject(&.empty?)
        outline.classes << ClassDecl.new(outline.path, TreeSitter.node_text(left, source), TreeSitter.node_start_row(node) + 1,
          bases, [] of String, [] of Member, {} of String => ClassDecl)
      end
    end

    # A class or a function (with its decorators), or nil.
    private def definition(node : LibTreeSitter::TSNode, source : String, path : String) : (ClassDecl | Member)?
      decorators = [] of String
      if TreeSitter.node_type(node) == "decorated_definition"
        TreeSitter.each_named_child(node) do |child|
          next unless TreeSitter.node_type(child) == "decorator"
          TreeSitter.first_named_child(child).try { |expr| decorators << code_text(expr, source) }
        end
        node = TreeSitter.field(node, "definition") || return
      end
      name = TreeSitter.field(node, "name").try { |n| TreeSitter.node_text(n, source) } || return
      line = TreeSitter.node_start_row(node) + 1

      case TreeSitter.node_type(node)
      when "class_definition"
        bases = [] of String
        TreeSitter.field(node, "superclasses").try do |list|
          TreeSitter.each_named_child(list) do |base|
            bases << TreeSitter.node_text(base, source) unless TreeSitter.node_type(base) == "keyword_argument"
          end
        end
        members = [] of Member
        inner = {} of String => ClassDecl
        TreeSitter.field(node, "body").try do |body|
          TreeSitter.each_named_child(body) do |stmt|
            case TreeSitter.node_type(stmt)
            when "expression_statement"
              attribute(stmt, source, path).try { |m| members << m }
            else
              case decl = definition(stmt, source, path)
              when ClassDecl then inner[decl.name] = decl
              when Member    then members << decl
              end
            end
          end
        end
        ClassDecl.new(path, name, line, bases, decorators, members, inner)
      when "function_definition"
        params = [] of Param
        TreeSitter.field(node, "parameters").try do |list|
          TreeSitter.each_named_child(list) { |p| param(p, source).try { |v| params << v } }
        end
        returns = TreeSitter.field(node, "return_type").try { |r| TreeSitter.node_text(r, source) }
        Member.new(path, name, line, decorators, nil, nil, params, returns)
      end
    end

    # `name: T = value`, `name: T` or `name = value` in a class body.
    private def attribute(stmt : LibTreeSitter::TSNode, source : String, path : String) : Member?
      assignment = TreeSitter.first_named_child(stmt) || return
      return unless TreeSitter.node_type(assignment) == "assignment"
      left = TreeSitter.field(assignment, "left") || return
      return unless TreeSitter.node_type(left) == "identifier"
      hint = TreeSitter.field(assignment, "type").try { |t| TreeSitter.node_text(t, source) }
      right = TreeSitter.field(assignment, "right")
      # `x = (\n    Mutation.Field()\n)`, black's wrap for a long line.
      while right && TreeSitter.node_type(right) == "parenthesized_expression"
        right = TreeSitter.first_named_child(right)
      end
      value = right.try { |r| code_text(r, source) }
      Member.new(path, TreeSitter.node_text(left, source), TreeSitter.node_start_row(stmt) + 1,
        [] of String, hint, value, nil, nil)
    end

    # Node text with its comments cut out. A call wrapped over several lines
    # carries `# note`s that would otherwise glue onto the next argument
    # when the text is split on commas, losing every argument after it.
    private def code_text(node : LibTreeSitter::TSNode, source : String) : String
      pos = LibTreeSitter.ts_node_start_byte(node).to_i
      stop = LibTreeSitter.ts_node_end_byte(node).to_i
      String.build do |io|
        TreeSitter.walk(node) do |n|
          next unless TreeSitter.node_type(n) == "comment"
          from = LibTreeSitter.ts_node_start_byte(n).to_i
          io << source.byte_slice(pos, from - pos)
          pos = LibTreeSitter.ts_node_end_byte(n).to_i
        end
        io << source.byte_slice(pos, stop - pos)
      end
    end

    private def param(node : LibTreeSitter::TSNode, source : String) : Param?
      case TreeSitter.node_type(node)
      when "identifier"
        Param.new(TreeSitter.node_text(node, source), nil, nil)
      when "typed_parameter"
        name = TreeSitter.first_named_child(node) || return
        return unless TreeSitter.node_type(name) == "identifier"
        Param.new(TreeSitter.node_text(name, source), TreeSitter.field(node, "type").try { |t| TreeSitter.node_text(t, source) }, nil)
      when "default_parameter", "typed_default_parameter"
        name = TreeSitter.field(node, "name") || return
        Param.new(TreeSitter.node_text(name, source),
          TreeSitter.field(node, "type").try { |t| TreeSitter.node_text(t, source) },
          TreeSitter.field(node, "value").try { |v| TreeSitter.node_text(v, source) })
      end
    end

    private def read_import(node : LibTreeSitter::TSNode, source : String, outline : FileOutline)
      from = nil.as(Array(String)?)
      TreeSitter.each_named_child(node) do |child|
        case TreeSitter.node_type(child)
        when "relative_import"
          dir = File.dirname(outline.path)
          rest = [] of String
          TreeSitter.each_named_child(child) do |sub|
            case TreeSitter.node_type(sub)
            when "import_prefix" then (TreeSitter.node_text(sub, source).size - 1).times { dir = File.dirname(dir) }
            when "dotted_name"   then rest = TreeSitter.node_text(sub, source).split('.')
            end
          end
          from = [dir] + rest
        when "dotted_name"
          dotted = TreeSitter.node_text(child, source).split('.')
          if from.nil? && TreeSitter.node_type(node) == "import_from_statement"
            from = dotted
          elsif from
            outline.imports[dotted.last] = from + dotted
          end
          # `import a.b.c` binds `a`, which spells the full path anyway.
        when "aliased_import"
          target = TreeSitter.field(child, "name").try { |n| TreeSitter.node_text(n, source).split('.') } || next
          alias_name = TreeSitter.field(child, "alias").try { |n| TreeSitter.node_text(n, source) } || next
          outline.imports[alias_name] = from ? from + target : target
        end
      end
    end

    # Positional and keyword argument source text of `callee(...)`, or nil
    # when `text` is not a single call.
    def call_args(text : String) : {Array(String), Hash(String, String)}?
      open = text.index('(') || return
      return unless text.ends_with?(')') && text[0, open].strip.matches?(/\A[\w.]+\z/)
      positional = [] of String
      keywords = {} of String => String
      TopLevelSplit.split(text[(open + 1)...-1], ',', TopLevelSplit::Rules::PYTHON).each do |arg|
        arg = arg.strip
        next if arg.empty?
        if kw = arg.match(/\A(\w+)\s*=(?!=)\s*(.*)\z/m)
          keywords[kw[1]] = kw[2]
        else
          positional << arg
        end
      end
      {positional, keywords}
    end

    # Callee of `text` when it is a call (`graphene.String(...)` => `graphene.String`).
    def callee(text : String) : String?
      open = text.index('(') || return
      name = text[0, open].strip
      name if text.rstrip.ends_with?(')') && name.matches?(/\A[\w.]+\z/)
    end

    # Value of a plain string literal, else nil.
    def string_literal(text : String?) : String?
      text.try(&.strip.match(/\A[rRuU]?(["'])([^"'\\]*)\1\z/)).try(&.[2])
    end

    # The `to_camel_case` both libraries share: `user_id` => `userId`,
    # with an empty component (a doubled `_`) kept as `_`.
    def camel_case(name : String) : String
      parts = name.split('_')
      String.build do |io|
        io << parts.first
        parts.skip(1).each { |p| io << (p.empty? ? "_" : p.capitalize) }
      end
    end
  end
end
