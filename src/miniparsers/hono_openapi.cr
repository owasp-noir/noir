require "./js_route_extractor"

module Noir::TSContractExtractor
  # AST nodes belong to one parse. Only value identities (initializer byte
  # offsets), import names and extracted facts survive the per-file pass.
  alias HonoRef = UInt32 | String
  alias HonoBinding = Tuple(HonoFile, UInt32)
  record HonoDescriptor, route : Route, middleware : String
  record HonoRegistration, receiver : HonoRef?, descriptor : HonoRef?, line : Int32
  record HonoEndpoint, route : Route, file : String, line : Int32, prefix : String, middleware : String?, unresolved : Bool = false

  class HonoFile
    getter path : String
    getter imports = {} of String => Tuple(String, String)
    getter forwards = {} of String => Tuple(String, String)
    getter exports = {} of String => HonoRef
    getter descriptors = {} of UInt32 => HonoDescriptor
    getter registrations = [] of HonoRegistration
    getter apps = Set(UInt32).new
    getter docs = [] of Tuple(HonoRef, Route)
    getter mounts = [] of Tuple(HonoRef, String, HonoRef)
    property file_prefixes = [] of String

    def initialize(@path : String)
    end
  end

  # Resolve local bindings in their enclosing block. Initializers with the
  # same name in two factories must never exchange descriptors or guards.
  private class HonoContext < Context
    getter file : HonoFile
    @values = {} of Tuple(Pointer(Void), String) => LibTreeSitter::TSNode

    def initialize(source : String, @file : HonoFile)
      super(source)
    end

    def declare(node, name, value)
      each_scope(node) do |scope|
        @values[{scope, name}] = TreeSitter.unwrap_expression(value)
        break
      end
    end

    def parameter(scope, node)
      pattern = TreeSitter.field(node, "pattern") || TreeSitter.field(node, "left") || node
      return unless TreeSitter.node_type(pattern) == "identifier"
      # A parameter shadows outer bindings, but its runtime value is unknown.
      @values[{scope.id, TreeSitter.node_text(pattern, source)}] = scope
    end

    def value(node, name) : LibTreeSitter::TSNode?
      each_scope(node) { |scope| @values[{scope, name}]?.try { |value| return value } }
      nil
    end

    private def each_scope(node, &)
      while parent = TreeSitter.parent(node)
        node = parent
        if TreeSitter.node_type(node).in?("statement_block", "program", "arrow_function", "function_declaration", "function_expression", "method_definition", "catch_clause")
          yield node.id
        end
      end
    end
  end

  def hono_candidate?(content : String) : Bool
    content.includes?("Hono") || content.includes?("openapi") || content.matches?(/\.\s*route\s*\(|\bexport\s*\{[^}]*\}\s*from\s*['"]\./)
  end

  def hono_file(source : String, path : String, *, descriptors : Bool = true) : HonoFile
    file = HonoFile.new(path)
    TreeSitter.parse_js_family(source, path) do |root|
      ctx = HonoContext.new(source, file)
      each_top_level(root, ctx) { |name, node| ctx.decls[name] = node if name }
      TreeSitter.walk(root) do |node|
        case TreeSitter.node_type(node)
        when "variable_declarator"
          name = TreeSitter.field(node, "name") || next
          value = TreeSitter.field(node, "value") || next
          ctx.declare(node, text(name, ctx), value)
        when "formal_parameters"
          scope = TreeSitter.parent(node) || next
          TreeSitter.each_named_child(node) { |param| ctx.parameter(scope, param) }
        when "arrow_function", "catch_clause"
          TreeSitter.field(node, "parameter").try { |param| ctx.parameter(node, param) }
        when "import_statement"
          hono_imports(node, ctx, file)
        end
      end
      TreeSitter.walk(root) do |node|
        case TreeSitter.node_type(node)
        when "new_expression"
          constructor = TreeSitter.field(node, "constructor") || next
          name = text(constructor, ctx)
          if imported = file.imports[name]?
            next unless imported[0].in?("hono", "@hono/zod-openapi")
            name = imported[1]
          end
          file.apps << LibTreeSitter.ts_node_start_byte(node) if name.in?("Hono", "OpenAPIHono")
        when "call_expression"
          hono_call(node, ctx, file, descriptors)
        when "export_statement"
          hono_exports(node, ctx, file)
        end
      end
    end
    file
  end

  private def hono_imports(node, ctx, file)
    source = TreeSitter.field(node, "source").try { |arg| string_value(arg, ctx) } || return
    clause = TreeSitter.first_named_child(node) || return
    TreeSitter.each_named_child(clause) do |child|
      case TreeSitter.node_type(child)
      when "identifier"
        file.imports[text(child, ctx)] = {source, "default"}
      when "named_imports"
        TreeSitter.each_named_child(child) do |item|
          name = TreeSitter.field(item, "name") || next
          local = TreeSitter.field(item, "alias") || name
          file.imports[text(local, ctx)] = {source, text(name, ctx)}
        end
      end
    end
  end

  private def hono_exports(node, ctx, file)
    if value = TreeSitter.field(node, "value")
      hono_ref(value, ctx).try { |ref| file.exports["default"] = ref }
    elsif decl = TreeSitter.field(node, "declaration")
      TreeSitter.each_named_child(decl) do |item|
        name = TreeSitter.field(item, "name") || next
        value = TreeSitter.field(item, "value") || next
        hono_ref(value, ctx).try { |ref| file.exports[text(name, ctx)] = ref }
      end
    else
      source = TreeSitter.field(node, "source").try { |arg| string_value(arg, ctx) }
      TreeSitter.walk(node) do |item|
        next unless TreeSitter.node_type(item) == "export_specifier"
        name = TreeSitter.field(item, "name") || next
        exported = TreeSitter.field(item, "alias") || name
        if source
          file.forwards[text(exported, ctx)] = {source, text(name, ctx)}
        else
          hono_ref(name, ctx).try { |ref| file.exports[text(exported, ctx)] = ref }
        end
      end
    end
  end

  private def hono_ref(expr, ctx) : HonoRef?
    node = TreeSitter.unwrap_expression(expr)
    32.times do
      case TreeSitter.node_type(node)
      when "identifier"
        name = text(node, ctx)
        node = ctx.value(node, name) || return name
      when "call_expression"
        return LibTreeSitter.ts_node_start_byte(node) if create_route_call?(node, ctx)
        return unless call_property(node, ctx).in?("openapi", "doc", "doc31", "route", "basePath", "use", "get", "post", "put", "patch", "delete", "on", "all")
        node = receiver(node) || return
      when "new_expression"
        return LibTreeSitter.ts_node_start_byte(node)
      else
        return
      end
    end
    nil
  end

  private def hono_call(node, ctx, file, descriptors)
    arg = first_arg(node) || return
    if create_route_call?(node, ctx)
      return unless descriptors
      obj = TreeSitter.node_type(arg) == "identifier" ? ctx.value(arg, text(arg, ctx)) : arg
      if obj && (descriptor = hono_descriptor(obj, TreeSitter.node_start_row(node) + 1, ctx))
        file.descriptors[LibTreeSitter.ts_node_start_byte(node)] = descriptor
      end
      return
    end

    property = call_property(node, ctx)
    return unless property.in?("openapi", "doc", "doc31", "route")
    app = receiver(node).try { |obj| hono_ref(obj, ctx) }
    line = TreeSitter.call_name_row(node) + 1
    case property
    when "openapi"
      file.registrations << HonoRegistration.new(app, hono_ref(arg, ctx), line) if second_arg(node)
    when "doc", "doc31"
      if app && (path = string_value(arg, ctx))
        file.docs << {app, Route.new("GET", path, line)}
      end
    when "route"
      child = second_arg(node).try { |expr| hono_ref(expr, ctx) }
      if app && child && (prefix = string_value(arg, ctx))
        file.mounts << {app, prefix, child}
      end
    end
  end

  # Single-source entry point used by extractor clients without a scan index.
  def hono_openapi(source : String, path : String = "") : Array(Route)
    hono_endpoints([hono_file(source, path)]) { nil }.map do |entry|
      Route.new(entry.route.method, URLPath.join(entry.prefix, entry.route.path), entry.line).tap do |route|
        route.params.concat(entry.route.params)
      end
    end
  end

  def hono_endpoints(files : Array(HonoFile), &resolve_import : String, String -> String?) : Array(HonoEndpoint)
    HonoProject.new(files, &resolve_import).endpoints
  end

  private class HonoProject
    @imports = {} of Tuple(HonoFile, String) => HonoBinding
    @prefixes = {} of String => Array(String)

    def initialize(@files : Array(HonoFile), &resolve_import : String, String -> String?)
      by_path = @files.to_h { |file| {File.expand_path(file.path), file} }
      @files.each do |file|
        file.imports.each do |name, (specifier, exported)|
          target = resolve_import.call(file.path, specifier).try { |path| by_path[path]? } || next
          seen = Set(Tuple(HonoFile, String)).new
          while (forward = target.forwards[exported]?) && seen.add?({target, exported})
            next_file = resolve_import.call(target.path, forward[0]).try { |path| by_path[path]? } || break
            target, exported = next_file, forward[1]
          end
          id = target.exports[exported]?.as?(UInt32)
          @imports[{file, name}] = {target, id} if id
        end
      end
      collect_mounts
    end

    private def binding(file, ref) : HonoBinding?
      case ref
      when UInt32 then {file, ref}
      when String then @imports[{file, ref}]?
      end
    end

    private def app_binding(file, ref) : HonoBinding?
      target = binding(file, ref)
      target if target && target[0].apps.includes?(target[1])
    end

    private def key(app : HonoBinding) : String
      "#{app[0].path}:#{app[1]}"
    end

    def endpoints : Array(HonoEndpoint)
      results = [] of HonoEndpoint
      used = Set(HonoBinding).new
      visible = Set(HonoFile).new
      uncertain = Set(HonoBinding).new
      incomplete = Set(HonoFile).new
      @files.each do |file|
        file.registrations.each do |call|
          target = binding(file, call.descriptor)
          unless app = app_binding(file, call.receiver)
            uncertain << target if target
            next
          end
          visible << file
          unless target && (descriptor = target[0].descriptors[target[1]]?)
            incomplete << file
            file.imports.each_key { |name| @imports[{file, name}]?.try { |imported| uncertain << imported } }
            next
          end
          used << target
          visible << target[0]
          @prefixes.fetch(key(app), [""]).each do |prefix|
            results << HonoEndpoint.new(descriptor.route, file.path, call.line, prefix, descriptor.middleware)
          end
        end
        file.docs.each do |receiver, route|
          next unless app = app_binding(file, receiver)
          @prefixes.fetch(key(app), [""]).each { |prefix| results << HonoEndpoint.new(route, file.path, route.line, prefix, nil) }
        end
      end

      # Only suppress unused descriptors in modules whose registrations we
      # could follow. Another app in the scan says nothing about a standalone
      # contract module, and a dynamic registration may select a local/import.
      @files.each do |file|
        file.descriptors.each do |id, descriptor|
          next if used.includes?({file, id})
          exported = file.exports.has_value?(id)
          next if !exported && visible.includes?(file) && !incomplete.includes?(file) && !uncertain.includes?({file, id})
          results << HonoEndpoint.new(descriptor.route, file.path, descriptor.route.line, "", "", unresolved: true)
        end
      end
      results
    end

    private def collect_mounts
      edges = [] of Tuple(String, String, String)
      mounted = Set(HonoBinding).new
      imported_prefixes = Hash(HonoFile, Array(String)).new { |hash, file| hash[file] = [] of String }
      @files.each do |file|
        file.mounts.each do |receiver, prefix, target|
          parent = app_binding(file, receiver) || next
          child = app_binding(file, target) || next
          edges << {key(parent), prefix, key(child)}
          mounted << child
          imported_prefixes[child[0]] << prefix unless child[0] == file
        end
      end
      @files.each do |file|
        # RouterMountScanner can also read mounts outside known Hono apps.
        # Keep those prefixes, removing ones we can assign to a specific app.
        fallback = file.file_prefixes - imported_prefixes[file]
        file.apps.each do |id|
          app = {file, id}
          next if mounted.includes?(app) && (fallback.empty? || imported_prefixes[file].empty?)
          @prefixes[key(app)] = fallback.empty? ? [""] : fallback.dup
        end
      end
      JSRouteExtractor.propagate_mount_prefixes(edges, @prefixes)
    end
  end
end
