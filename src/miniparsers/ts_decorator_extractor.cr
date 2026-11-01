require "../ext/tree_sitter/tree_sitter"

# Decorated classes of a TypeScript / JavaScript source, read off the
# TypeScript AST: the class's decorators, and per decorated method its
# decorators and decorated parameters. Shared by the decorator-controller
# analyzers (NestJS, Midway, tsoa, routing-controllers, Ts.ED, inversify,
# n8n) and the NestJS auth tagger, so a decorator split over lines, an
# argument holding `)` in a string, or `@Get(` inside a string or comment
# read the same everywhere.
#
# Decorator arguments are kept as source text: the callers decode them with
# their own literal tables (`'users'`, `RouteKey.User`, `{ path, version }`).
module Noir::TsDecoratorExtractor
  # `@Name(args)` (`called`) or a bare `@Name`. `name` is the callee text
  # (`Get`, `requestBody.file`); `row` is 0-based.
  record Decorator, name : String, text : String, args : Array(String), called : Bool, row : Int32

  # A parameter with at least one decorator. `name` is the bound identifier
  # (nil for a destructuring pattern), `type_text` its annotation.
  record Parameter, name : String?, type_text : String?, decorators : Array(Decorator)

  # A decorated method. `row` is the declaration's own row (its first
  # modifier or its name), `body_start`/`body_end` the byte range inside its
  # braces and `body_row` the row of the `{`.
  record Method, name : String, decorators : Array(Decorator), params : Array(Parameter),
    row : Int32, end_row : Int32, body_start : Int32?, body_end : Int32?, body_row : Int32 do
    def start_row : Int32
      decorators.first?.try(&.row) || row
    end
  end

  # A class with a decorator of its own or a decorated method.
  record ClassDecl, name : String, decorators : Array(Decorator), methods : Array(Method),
    row : Int32, end_row : Int32 do
    def start_row : Int32
      decorators.first?.try(&.row) || row
    end
  end

  CLASS_TYPES = {"class_declaration", "abstract_class_declaration", "class"}

  # Every decorated class in `source`, outer classes first. `.js`/`.jsx`
  # go through the TypeScript/TSX grammar too: the JavaScript grammar has no
  # parameter decorators, which Babel-compiled Nest code uses.
  def self.extract(source : String, path : String) : Array(ClassDecl)
    classes = [] of ClassDecl
    language = path.ends_with?(".tsx") || path.ends_with?(".jsx") ? LibTreeSitter.tree_sitter_tsx : LibTreeSitter.tree_sitter_typescript
    Noir::TreeSitter.parse(source, language) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless CLASS_TYPES.includes?(Noir::TreeSitter.node_type(node))
        decl = read_class(node, source)
        classes << decl if decl && (!decl.decorators.empty? || !decl.methods.empty?)
      end
    end
    classes
  end

  private def self.read_class(node : LibTreeSitter::TSNode, source : String) : ClassDecl?
    body = Noir::TreeSitter.field(node, "body") || return
    decorators = [] of Decorator
    # `@Controller() export class X {}`: the decorators sit on the export.
    if (parent = Noir::TreeSitter.parent(node)) && Noir::TreeSitter.node_type(parent) == "export_statement"
      collect_decorators(parent, source, decorators)
    end
    collect_decorators(node, source, decorators)

    methods = [] of Method
    pending = [] of Decorator
    # Member decorators precede their member as siblings in the class body.
    Noir::TreeSitter.each_named_child(body) do |member|
      case Noir::TreeSitter.node_type(member)
      when "decorator"
        pending << decorator(member, source)
      when "comment"
        next
      when "method_definition"
        # The JavaScript grammar would nest them in the method instead.
        collect_decorators(member, source, pending)
        methods << read_method(member, source, pending) unless pending.empty?
        pending = [] of Decorator
      else
        pending = [] of Decorator
      end
    end

    name = Noir::TreeSitter.field(node, "name").try { |n| Noir::TreeSitter.node_text(n, source) } || ""
    ClassDecl.new(name, decorators, methods, Noir::TreeSitter.node_start_row(node), Noir::TreeSitter.node_end_row(node))
  end

  private def self.read_method(node : LibTreeSitter::TSNode, source : String, decorators : Array(Decorator)) : Method
    name = Noir::TreeSitter.field(node, "name").try { |n| Noir::TreeSitter.node_text(n, source) } || ""
    params = [] of Parameter
    Noir::TreeSitter.field(node, "parameters").try do |list|
      Noir::TreeSitter.each_named_child(list) do |param|
        next unless {"required_parameter", "optional_parameter"}.includes?(Noir::TreeSitter.node_type(param))
        param_decorators = [] of Decorator
        collect_decorators(param, source, param_decorators)
        next if param_decorators.empty?
        pattern = Noir::TreeSitter.field(param, "pattern")
        bound = pattern.try { |p| Noir::TreeSitter.node_text(p, source) if Noir::TreeSitter.node_type(p) == "identifier" }
        type = Noir::TreeSitter.field(param, "type").try { |t| Noir::TreeSitter.first_named_child(t) }
        params << Parameter.new(bound, type.try { |t| Noir::TreeSitter.node_text(t, source) }, param_decorators)
      end
    end

    # The declaration starts after the decorators: at its first modifier or
    # its name, whichever grammar put the decorators where.
    row = Noir::TreeSitter.node_start_row(node)
    LibTreeSitter.ts_node_child_count(node).times do |i|
      child = LibTreeSitter.ts_node_child(node, i)
      next if Noir::TreeSitter.node_type(child) == "decorator"
      row = Noir::TreeSitter.node_start_row(child)
      break
    end

    body = Noir::TreeSitter.field(node, "body")
    body_start = body.try { |b| LibTreeSitter.ts_node_start_byte(b).to_i + 1 }
    body_end = body.try { |b| LibTreeSitter.ts_node_end_byte(b).to_i - 1 }
    Method.new(name, decorators, params, row, Noir::TreeSitter.node_end_row(node),
      body_start, body_end, body.try { |b| Noir::TreeSitter.node_start_row(b) } || row)
  end

  private def self.collect_decorators(node : LibTreeSitter::TSNode, source : String, into : Array(Decorator))
    Noir::TreeSitter.each_named_child(node) do |child|
      into << decorator(child, source) if Noir::TreeSitter.node_type(child) == "decorator"
    end
  end

  private def self.decorator(node : LibTreeSitter::TSNode, source : String) : Decorator
    text = Noir::TreeSitter.node_text(node, source)
    row = Noir::TreeSitter.node_start_row(node)
    expr = Noir::TreeSitter.first_named_arg(node)
    if expr && Noir::TreeSitter.node_type(expr) == "call_expression" && (callee = Noir::TreeSitter.field(expr, "function"))
      args = [] of String
      Noir::TreeSitter.field(expr, "arguments").try do |list|
        Noir::TreeSitter.each_named_arg(list) { |arg| args << Noir::TreeSitter.node_text(arg, source) }
      end
      Decorator.new(Noir::TreeSitter.node_text(callee, source), text, args, true, row)
    else
      Decorator.new(expr.try { |e| Noir::TreeSitter.node_text(e, source) } || "", text, [] of String, false, row)
    end
  end
end
