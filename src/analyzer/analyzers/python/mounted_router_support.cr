require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"
require "./python_helper"

module Analyzer::Python
  # Decorator routes on a receiver, plus `parent.<mount>(child, prefix=...)`
  # calls that prefix every route of `child` — the shape AWS Chalice
  # blueprints and Lambda Powertools routers share. The adapter reads one
  # file into a `FileScan`; `emit_mounted_routes` resolves each mount target
  # (same-file name, `from m import router`, or `m.router`) and joins the
  # prefixes. Mounts are one level deep: neither framework nests them.
  module MountedRouterSupport
    record Route, receiver : ::String, path : ::String, methods : Array(::String),
      params : Array(Param), line : Int32, callees : Array(Callee), tags : Array(Tag) = [] of Tag
    # `name` is the mounted variable; `local` when it resolved to this file.
    record Mount, file : ::String, name : ::String, prefix : ::String, local : Bool
    record FileScan, path : ::String, routes : Array(Route), mounts : Array(Mount)

    MOUNT_TARGET_RE = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?\z/

    # `<x>.<attribute>(target, ...)` mounts: the target is the first
    # argument or `target_keyword=`, the prefix `prefix_keyword=` or the
    # positional argument at `prefix_index`.
    private def collect_mounts(source : ::String, path : ::String, base_path : ::String, attribute : ::String,
                               target_keyword : ::String, prefix_keyword : ::String, prefix_index : Int32) : Array(Mount)
      mounts = [] of Mount
      return mounts unless source.includes?(".#{attribute}(")

      imports = mount_imports(base_path, path, source)
      Noir::TreeSitterPythonRouteExtractor.extract_attribute_calls(source, [attribute]).each do |call|
        target = call.keywords[target_keyword]? || call.args[0]?
        prefix = call.keywords[prefix_keyword]? || call.args[prefix_index]? || ""
        resolve_mount(target, prefix, path, imports).try { |mount| mounts << mount } if target
      end
      mounts
    end

    # Imports resolved from the scan base, then from the file's own
    # directory: a Lambda/Chalice app nested below the scan root imports
    # its modules relative to its own source root.
    private def mount_imports(base_path : ::String, path : ::String, source : ::String) : Hash(::String, Tuple(::String, Int32))
      imports = find_imported_modules(base_path, path, source)
      local_base = File.dirname(path)
      return imports if local_base == base_path
      find_imported_modules(local_base, path, source).each do |name, info|
        existing = imports[name]?
        imports[name] = info if existing.nil? || existing[0].empty?
      end
      imports
    end

    private def resolve_mount(target : ::String, prefix : ::String, path : ::String,
                              imports : Hash(::String, Tuple(::String, Int32))) : Mount?
      return unless target.matches?(MOUNT_TARGET_RE)
      head, _, tail = target.partition('.')
      file = imports[head]?.try(&.first)
      if tail.empty?
        return Mount.new(path, head, prefix, true) if file.nil? || file.empty?
        Mount.new(file, head, prefix, false)
      elsif file && !file.empty?
        Mount.new(file, tail, prefix, false)
      end
    end

    # The decorated handler's body (comments stripped, for param scans) and
    # its callees.
    private def handler_body(lines : Array(::String), def_line : Int32, path : ::String,
                             base_path : ::String, source : ::String) : Tuple(::String, Array(Callee))
      return {"", [] of Callee} if def_line < 0
      body = extract_function_body(lines, def_line)
      callees = build_callees_from(body, def_line + 1, path, definition_base_path: base_path, source: source)
      {body.lines.map { |line| strip_python_comment(line) }.join('\n'), callees}
    end

    # `<accessor>.<attr>.get("k")` / `["k"]` reads (also through a local
    # alias of the accessor), typed by `attrs`; a bare `.json_body` read with
    # no keyed access becomes one `body` JSON param.
    private def request_params(body : ::String, accessor : ::String, alias_re : Regex,
                               attrs : Hash(::String, ::String)) : Array(Param)
      readers = [accessor]
      body.scan(alias_re) { |m| readers << m[1] }
      params = [] of Param
      body.scan(PythonEngine::DICT_READ_RE) do |m|
        receiver, _, attr = m[1].rpartition('.')
        next unless (type = attrs[attr]?) && readers.any? { |r| receiver == r || receiver.ends_with?(".#{r}") }
        params << Param.new(m[2]? || m[3], "", type)
      end
      params << Param.new("body", "", "json") if body.includes?(".json_body") && params.none? { |p| p.param_type == "json" }
      params
    end

    private def emit_mounted_routes(scans : Array(FileScan)) : Nil
      receivers = Hash(::String, Set(::String)).new
      scans.each { |scan| receivers[File.expand_path(scan.path)] = scan.routes.map(&.receiver).to_set }

      prefixes = Hash(Tuple(::String, ::String), Array(::String)).new
      scans.each do |scan|
        scan.mounts.each do |mount|
          file = File.expand_path(mount.file)
          next unless names = receivers[file]?
          # An aliased import (`from m import router as r`) hides the
          # variable's own name: mount every router of that module.
          targets = names.includes?(mount.name) ? [mount.name] : (mount.local ? [] of ::String : names.to_a)
          targets.each { |name| (prefixes[{file, name}] ||= [] of ::String) << mount.prefix }
        end
      end

      scans.each do |scan|
        file = File.expand_path(scan.path)
        scan.routes.each do |route|
          (prefixes[{file, route.receiver}]?.try(&.uniq) || [""]).each do |prefix|
            # Both frameworks serve a mounted "/" at the bare prefix.
            url = route.path == "/" && !prefix.empty? ? Helper.normalize_path(prefix) : Helper.normalized_join(prefix, route.path)
            route.methods.each do |method|
              endpoint = Endpoint.new(url, method, get_filtered_params(method, route.params),
                Details.new(PathInfo.new(scan.path, route.line)))
              route.tags.each { |tag| endpoint.add_tag(tag) }
              route.callees.each { |callee| endpoint.push_callee(callee) }
              result << endpoint
            end
          end
        end
      end
    end
  end
end
