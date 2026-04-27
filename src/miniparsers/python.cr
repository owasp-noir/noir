require "../ext/tree_sitter/tree_sitter"
require "../utils/parser_limit"
require "./import_graph"

# Python source-file parser used by the Flask analyzer to resolve
# routing-relevant globals (Blueprint / Namespace / Api instances)
# across files. Originally a hand-rolled token consumer paired with
# `minilexers/python.cr`; rewritten to walk the vendored tree-sitter
# Python grammar so we shed the legacy lexer (now deleted) and get
# accurate handling of multi-line strings, fstrings, parenthesised
# imports, and similar shapes that the regex/token approach couldn't
# express cleanly.
#
# The public surface kept stable for Flask:
#
#   * `PythonParser.new(path, content, parsers, depth = 0)` — same
#     constructor shape minus the now-irrelevant `tokens` argument.
#   * `parser.@global_variables : Hash(String, GlobalVariables)` —
#     populated for the file at `path` plus every module reachable
#     through its `import` / `from … import …` statements
#     (recursive, with depth bounded by `ParserLimit`).
#   * Per-variable `GlobalVariables` struct with `name`, `type`,
#     `value`, `path` fields. `type` is `"str"` for string
#     assignments, the callee identifier for `name = Foo(...)` calls
#     (including dotted forms like `Namespace.model`), `nil`
#     otherwise.
#
# `ImportModel` stays in tree but isn't populated by this rewrite —
# nothing reads `parser.@import_statements`. We keep the class for
# any external referrers that might construct one for logging.
class PythonParser
  property path : String

  def initialize(@path : String,
                 content : String,
                 @parsers : Hash(String, PythonParser),
                 @visited : Array(String) = Array(String).new,
                 depth : Int32 = 0)
    @global_variables = Hash(String, GlobalVariables).new
    @basedir = File.dirname(@path)
    while @basedir != "" && File.exists?(@basedir + "/__init__.py")
      @basedir = File.dirname(@basedir)
    end

    @depth = depth
    @visited << path

    parse(content)
  end

  def parse(content : String)
    Noir::TreeSitter.parse_python(content) do |root|
      extract_imports(root, content)
      extract_globals(root, content)
    end
  end

  # ---- module-level globals ---------------------------------------

  private def extract_globals(root : LibTreeSitter::TSNode, source : String)
    Noir::TreeSitter.each_named_child(root) do |node|
      next unless Noir::TreeSitter.node_type(node) == "expression_statement"
      Noir::TreeSitter.each_named_child(node) do |child|
        next unless Noir::TreeSitter.node_type(child) == "assignment"
        name, type, value = analyse_assignment(child, source)
        next if name.empty?
        @global_variables[name] = GlobalVariables.new(name, type, value, @path)
      end
    end
  end

  # `assignment` shape under tree-sitter-python:
  #
  #   simple:   `x = "hello"` →  identifier=name, string=rhs
  #   typed:    `x: T = ...`  →  identifier, type, rhs
  #   call:     `x = Foo(args)` → identifier, call(callee=identifier|attribute, args)
  #
  # We map this to the legacy `(name, type?, value)` triple.
  private def analyse_assignment(node : LibTreeSitter::TSNode, source : String) : Tuple(String, String?, String)
    name = ""
    type : String? = nil
    value = ""
    saw_rhs = false

    Noir::TreeSitter.each_named_child(node) do |child|
      ty = Noir::TreeSitter.node_type(child)

      if !saw_rhs && ty == "identifier" && name.empty?
        name = Noir::TreeSitter.node_text(child, source)
        next
      end

      if !saw_rhs && ty == "type"
        type = first_identifier_text(child, source)
        next
      end

      next if saw_rhs

      case ty
      when "string"
        type ||= "str"
        value = decode_string(child, source)
      when "call"
        callee = first_named_child(child)
        type ||= callee_name(callee, source) if callee
        value = Noir::TreeSitter.node_text(child, source)
      else
        value = Noir::TreeSitter.node_text(child, source)
      end
      saw_rhs = true
    end

    {name, type, value}
  end

  private def callee_name(callee : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(callee)
    when "identifier"
      Noir::TreeSitter.node_text(callee, source)
    when "attribute"
      # Dotted forms like `Namespace.model(...)` — the legacy parser
      # surfaced the full dotted text as `type`. Tree-sitter wraps
      # the whole expression as `attribute`, so node_text gives us
      # the same shape.
      Noir::TreeSitter.node_text(callee, source)
    else
      ""
    end
  end

  private def first_identifier_text(node : LibTreeSitter::TSNode, source : String) : String
    Noir::TreeSitter.each_named_child(node) do |child|
      return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "identifier"
    end
    ""
  end

  private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
    buf = String.build do |io|
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "string_content"
          io << Noir::TreeSitter.node_text(child, source)
        end
      end
    end
    buf
  end

  private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    count = LibTreeSitter.ts_node_named_child_count(node)
    return if count == 0
    LibTreeSitter.ts_node_named_child(node, 0_u32)
  end

  # ---- imports + recursive merge ----------------------------------

  # Walk every top-level `import` / `import_from` statement and
  # merge any reachable module's globals into ours, mirroring the
  # legacy parser's behaviour:
  #
  #   `import x.y`            → key globals as `x.y.<key>` for each
  #                              global the leaf module exports
  #   `import x as y`         → key as `y.<key>`
  #   `from x import a`       → key as `a` (or alias if `as`)
  #   `from x import *`       → merge all keys verbatim
  #   `from . import a`       → relative to the current file
  #
  # Bounded by `ParserLimit.allow_depth?(@depth)` so deep import
  # webs don't melt the scanner.
  private def extract_imports(root : LibTreeSitter::TSNode, source : String)
    Noir::TreeSitter.each_named_child(root) do |node|
      case Noir::TreeSitter.node_type(node)
      when "import_statement"
        handle_import_statement(node, source)
      when "import_from_statement"
        handle_import_from_statement(node, source)
      end
    end
  end

  # `import x` / `import x.y as z` / `import a, b as c`
  private def handle_import_statement(node : LibTreeSitter::TSNode, source : String)
    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "dotted_name"
        dotted = Noir::TreeSitter.node_text(child, source)
        merge_imported_module(dotted, dotted, prefix: "#{dotted}.")
      when "aliased_import"
        dotted, alias_name = aliased_import_parts(child, source)
        merge_imported_module(dotted, alias_name, prefix: "#{alias_name}.")
      end
    end
  end

  # `from x import a` / `from . import a` / `from x import *`
  private def handle_import_from_statement(node : LibTreeSitter::TSNode, source : String)
    relative = false
    relative_prefix = 0
    from_dotted = ""
    name_specs = [] of Tuple(String, String?, Bool) # name, alias, wildcard

    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "relative_import"
        relative = true
        relative_prefix = count_relative_dots(child, source)
        # `relative_import` may also wrap a `dotted_name` for
        # `from .foo import bar` — pick that up.
        Noir::TreeSitter.each_named_child(child) do |sub|
          if Noir::TreeSitter.node_type(sub) == "dotted_name"
            from_dotted = Noir::TreeSitter.node_text(sub, source)
          end
        end
      when "dotted_name"
        if from_dotted.empty? && !relative
          from_dotted = Noir::TreeSitter.node_text(child, source)
        else
          name_specs << {Noir::TreeSitter.node_text(child, source), nil, false}
        end
      when "aliased_import"
        dotted, alias_name = aliased_import_parts(child, source)
        name_specs << {dotted, alias_name, false}
      when "wildcard_import"
        name_specs << {"*", nil, true}
      end
    end

    base_dir = relative ? relative_base_dir(relative_prefix) : @basedir
    return unless base_dir
    full_module = from_dotted.empty? ? "" : from_dotted

    name_specs.each do |name, alias_name, wildcard|
      if wildcard
        # `from X import *` — resolve X, merge every global.
        next if full_module.empty?
        pyfile = resolve_python_module(base_dir, full_module)
        next unless pyfile
        next if @visited.includes?(pyfile)
        next unless ParserLimit.allow_depth?(@depth)
        sub = get_or_create_parser(pyfile)
        next unless sub
        @global_variables.merge!(sub.@global_variables)
        next
      end

      # Two import shapes need separate handling:
      #
      #   * Name lookup: `from lib import thing` where `lib.py`
      #     exists and `thing` is a global inside it. Resolve the
      #     from-path alone, then read `thing` out of its globals.
      #   * Submodule import: `from pkg import sub` /
      #     `from . import sub` where `pkg/sub.py` (or just
      #     `sub.py` for the relative form) is itself a module.
      #     Prefix-import all of its globals as `sub.<key>` —
      #     matches the legacy parser's `remain_import_parts =
      #     false` branch.
      #
      # Try name-lookup first when there's a from-path; fall back
      # to submodule import. The relative-only `from . import x`
      # case skips straight to submodule import since there's no
      # from-path to look in.
      local_name = alias_name || name

      if !full_module.empty?
        from_pyfile = resolve_python_module(base_dir, full_module)
        if from_pyfile && !@visited.includes?(from_pyfile) && ParserLimit.allow_depth?(@depth)
          sub = get_or_create_parser(from_pyfile)
          if sub && sub.@global_variables.has_key?(name)
            @global_variables[local_name] = sub.@global_variables[name]
            next
          end
        end
      end

      submodule_path = full_module.empty? ? name : "#{full_module}.#{name}"
      pyfile = resolve_python_module(base_dir, submodule_path)
      next unless pyfile
      next if @visited.includes?(pyfile)
      next unless ParserLimit.allow_depth?(@depth)
      sub = get_or_create_parser(pyfile)
      next unless sub

      sub.@global_variables.each do |k, v|
        @global_variables["#{local_name}.#{k}"] = v
      end
    end
  end

  private def aliased_import_parts(node : LibTreeSitter::TSNode, source : String) : Tuple(String, String)
    dotted = ""
    alias_name = ""
    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "dotted_name"
        dotted = Noir::TreeSitter.node_text(child, source)
      when "identifier"
        if dotted.empty?
          dotted = Noir::TreeSitter.node_text(child, source)
        else
          alias_name = Noir::TreeSitter.node_text(child, source)
        end
      end
    end
    {dotted, alias_name}
  end

  # `relative_import` wraps an `import_prefix` with one `.` per
  # parent directory hop. Count them.
  private def count_relative_dots(node : LibTreeSitter::TSNode, source : String) : Int32
    Noir::TreeSitter.each_named_child(node) do |child|
      if Noir::TreeSitter.node_type(child) == "import_prefix"
        return Noir::TreeSitter.node_text(child, source).size
      end
    end
    0
  end

  private def relative_base_dir(prefix_dots : Int32) : String?
    dir = File.dirname(@path)
    (prefix_dots - 1).times do
      dir = File.dirname(dir)
      return if dir.empty? || dir == "/"
    end
    dir
  end

  private def merge_imported_module(dotted : String, key_root : String, prefix : String)
    pyfile = resolve_python_module(@basedir, dotted)
    return unless pyfile
    return if @visited.includes?(pyfile)
    return unless ParserLimit.allow_depth?(@depth)

    sub = get_or_create_parser(pyfile)
    return unless sub

    sub.@global_variables.each do |k, v|
      @global_variables["#{prefix}#{k}"] = v
    end
  end

  # Walk a dotted Python module path under `base_dir`, preferring
  # packages (directories) over modules (`.py` files). Mirrors the
  # legacy parser's `parse_import_statements` resolution logic plus
  # `Noir::ImportGraph::Python.find_imported_package` — but returns
  # the full leaf `.py` path (not a name → path map) since we just
  # want to recurse into one specific module.
  private def resolve_python_module(base_dir : String, dotted : String) : String?
    segments = dotted.split(".")
    package_dir = base_dir
    py_path : String? = nil

    segments.each_with_index do |seg, i|
      candidate = File.join(package_dir, seg)
      py_guess = "#{candidate}.py"
      if File.directory?(candidate)
        package_dir = candidate
      elsif File.exists?(py_guess)
        py_path = py_guess
        break
      elsif File.exists?(File.join(package_dir, "__init__.py")) && i == segments.size - 1
        py_path = File.join(package_dir, "__init__.py")
        break
      else
        return
      end
    end

    if py_path.nil? && File.exists?(File.join(package_dir, "__init__.py"))
      py_path = File.join(package_dir, "__init__.py")
    end

    py_path
  end

  private def get_or_create_parser(pyfile : String) : PythonParser?
    return @parsers[pyfile] if @parsers.has_key?(pyfile)

    content = File.read(pyfile, encoding: "utf-8", invalid: :skip)
    sub = PythonParser.new(pyfile, content, @parsers, @visited.dup, depth: @depth + 1)
    @parsers[pyfile] = sub
    sub
  rescue File::NotFoundError | File::AccessDeniedError
    nil
  end

  # Class to model annotations — kept for API stability even though
  # this rewrite no longer populates it (Flask doesn't read
  # `@import_statements` directly).
  class ImportModel
    property name : String
    property path : String?
    property as_name : String?

    def initialize(@name : String, @path : String?, @as_name : String?)
    end

    def to_s
      if @path.nil?
        "#{@name} from {unknown}"
      elsif @as_name.nil?
        "#{@name} from #{@path}"
      else
        "#{@name} from #{@path} as #{@as_name}"
      end
    end
  end

  class GlobalVariables
    property name : String
    property type : String?
    property value : String
    property path : String

    def initialize(@name : String, @type : String?, @value : String, @path : String)
    end

    def to_s
      if @type.nil?
        "#{@name} = #{@value} (#{path})"
      else
        "#{@name} : #{@type} = #{@value} (#{path})"
      end
    end
  end
end
