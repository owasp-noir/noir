require "../../engines/crystal_engine"
require "../../../utils/url_path"

module Analyzer::Crystal
  class Kemal < CrystalEngine
    analyzer_for "crystal_kemal"

    # Only files inside a project whose `shard.yml` depends on `kemal`.
    # See `CrystalEngine#shard_dependencies` — `get "/path"` is the same
    # line in Kemal, Grip and Amber, so the manifest is what tells the
    # frameworks apart.
    protected def shard_dependencies : Array(String)
      ["kemal"]
    end

    NAMESPACE_PATTERN = /^(\s*)(?:(\w+)\.)?namespace\s+["'](.+?)["']/
    MOUNT_PATTERN     = /^\s*mount\s+["'](.+?)["']\s*,\s*(@{0,2}\w+)/
    # `router = Kemal::Router.new` / `typed : Kemal::Router = Kemal::Router.new("/pre")`
    # / `@@router ||= Kemal::Router.new`: group 1 = name, 2 = the router's
    # own prefix. These names are the only receivers whose `router.get "/x"`
    # is a route: `client.get "/x"` on an `HTTP::Client` (or a spec helper)
    # has the same shape.
    ROUTER_NEW_PATTERN = /(?:^|[^.\w@:])(@{0,2}\w+)\s*(?::\s*[\w:]+\s*)?(?:\|\|)?=\s*Kemal::Router\.new\b(?:\s*\(?\s*["']([^"']*)["'])?/
    # Any other plain `name = …`, which unbinds a router name reassigned to
    # something else (`router = HTTP::Client.new` in a later method). `||=`
    # keeps an existing binding, so it is not one.
    ASSIGN_PATTERN = /(?:^|[^.\w@:])(@{0,2}[a-z_]\w*)\s*(?::\s*[\w:]+\s*)?=(?![=~>])/
    # A `def`/`macro` line or a lambda literal: its `name = …` are parameter
    # defaults, not assignments.
    PARAM_DEFAULTS_LINE = /^\s*(?:(?:private|protected|abstract)\s+)?(?:def|macro)\b|->\s*\(/
    # `api.mount "/users", users` / `api.mount users`: group 1 = parent,
    # 2 = path, 3 = child. The bare DSL `mount` is `MOUNT_PATTERN`.
    ROUTER_MOUNT_PATTERN = /(?:^|[^.\w@])(@{0,2}\w+)\.mount\s*\(?\s*(?:["']([^"']*)["']\s*,\s*)?(@{0,2}\w+)/
    # `router.get "/x"`: group 1 = receiver, 2 = verb, 3 = path. The receiver
    # is checked against the file's `Kemal::Router` names by the caller.
    ROUTER_ROUTE_PATTERN = /(?:^|[^.\w@])(@{0,2}\w+)\.(get|post|put|delete|patch|head|options|ws|sse|query)\s*(?:\(\s*)?['"](.+?)['"]/
    # Compile-time macro var assignment, e.g. `{{namespace = Routes::API::V1}}`.
    # invidious sets it once, then registers 50+ routes as
    # `get "/…", {{namespace}}::Videos, :videos` — substituting it back lets
    # those routes resolve their controller and carry callees.
    MACRO_VAR_PATTERN = /\{\{\s*(\w+)\s*=\s*([A-Za-z_][\w:]*)\s*\}\}/
    # `serve_static false` / `serve_static(false)` — checked on every source
    # line, so the two fixed OR-ed `String#includes?` substring scans are
    # precompiled into a single regex union (one PCRE2 JIT scan per line
    # instead of two naive substring scans).
    SERVE_STATIC_DISABLED_RE = Regex.union("serve_static false", "serve_static(false)")

    @static_disabled_bases : Set(String) = Set(String).new
    @public_folders : Array(Tuple(String, String)) = [] of Tuple(String, String)
    @action_index : ActionIndex = ActionIndex.new
    # How a router is wired into the app, by router name: its DSL `mount`
    # paths, the `parent.mount "/p", child` calls it hangs under, and its
    # own `Kemal::Router.new("/pre")` prefix.
    record Wiring,
      mounts = {} of String => Array(String),
      parents = {} of String => Array(Tuple(String, String)),
      prefixes = {} of String => String

    # Router constants' wiring per Kemal project (see `project_key_for`).
    # Only constants: a local or instance variable's name means nothing in
    # another file.
    @project_wiring = {} of String => Wiring

    def analyze
      # Apps like invidious register routes as `get "/", Routes::Misc, :home`
      # with the handler defined in a separate controller file. Build the
      # cross-file action index up front so those routes can carry callees.
      if callees_needed?
        @action_index = build_crystal_action_index(get_files_by_extension(".cr"))
      end
      collect_project_mounts
      super
      collect_public_dir_endpoints(@public_folders, @static_disabled_bases)
      @result
    end

    # `mount "/api", USERS_ROUTER` usually sits in the app file while the
    # `Kemal::Router` it mounts lives in its own, so a per-file mount map
    # left those routes unprefixed. Collected before the parallel walk.
    private def collect_project_mounts
      scan_target_files.each do |path|
        next unless scan_accepts?(path)
        content = read_file_content(path) rescue next
        next unless content.includes?("mount") || content.includes?("Kemal::Router")
        wiring = @project_wiring[project_key_for(path)] ||= Wiring.new
        mask_crystal_heredocs(content.lines).each do |line|
          read_router_wiring(line, wiring, constants_only: true)
        end
      end
    end

    # The Kemal project a file belongs to: its nearest enclosing kemal
    # `shard.yml`, else its scan base. Two apps under one `-b` both name
    # their router `API`; keying on the base let each read the other's mounts.
    private def project_key_for(path : String) : String
      expanded = Noir::PathScope.expand(path)
      shard_roots.select { |root| Noir::PathScope.under_normalized_root?(expanded, root) }.max_by?(&.size) ||
        configured_base_for(path)
    end

    private def read_router_wiring(line : String, wiring : Wiring, constants_only : Bool = false) : Nil
      if line.includes?("mount")
        if match = line.match(MOUNT_PATTERN)
          (wiring.mounts[match[2]] ||= [] of String) << match[1] if !constants_only || constant_name?(match[2])
        elsif (match = line.match(ROUTER_MOUNT_PATTERN)) && (!constants_only || constant_name?(match[3]))
          (wiring.parents[match[3]] ||= [] of Tuple(String, String)) << {match[1], match[2]? || ""}
        end
      end
      if line.includes?("Kemal::Router") && (match = line.match(ROUTER_NEW_PATTERN))
        wiring.prefixes[match[1]] = match[2]? || "" if !constants_only || constant_name?(match[1])
      end
    end

    private def constant_name?(name : String) : Bool
      name[0].uppercase?
    end

    # Every full prefix a router's routes are served under: each chain of
    # mounts above it, then its own constructor prefix, the order
    # `Router#register_routes` joins them in. The file's own wiring wins over
    # the project's. A chain that loops back on itself is dropped, and a
    # router whose every chain loops keeps just its own prefix.
    private def router_prefixes(name : String, local : Wiring, project : Wiring?) : Array(String)
      mounted_prefixes(name, local, project, [] of String) || [own_router_prefix(name, local, project)]
    end

    private def own_router_prefix(name : String, local : Wiring, project : Wiring?) : String
      local.prefixes[name]? || project.try(&.prefixes[name]?) || ""
    end

    # nil when every chain above `name` is a cycle. `chain` is the path walked
    # so far, which also caps the depth (and the fan-out of a router mounted
    # under several parents at every level).
    private def mounted_prefixes(name : String, local : Wiring, project : Wiring?, chain : Array(String)) : Array(String)?
      return if chain.includes?(name) || chain.size > 8
      own = own_router_prefix(name, local, project)
      mounts = local.mounts[name]? || project.try(&.mounts[name]?)
      parents = local.parents[name]? || project.try(&.parents[name]?)
      return [own] unless mounts || parents

      chain += [name]
      result = [] of String
      mounts.try &.each { |mount| result << Noir::URLPath.join(mount, own) }
      parents.try &.each do |parent_name, sub_path|
        mounted_prefixes(parent_name, local, project, chain).try &.each do |prefix|
          result << Noir::URLPath.join(Noir::URLPath.join(prefix, sub_path), own)
        end
      end
      result.empty? ? nil : result.uniq!
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      # Cache-first: prefer detector-warmed CodeLocator content. Valid
      # UTF-8 is byte-identical to the previous File.read_lines path;
      # invalid bytes now skip (matching every other Crystal analyzer)
      # instead of raising.
      lines = mask_crystal_heredocs(read_file_content(path).lines)
      file_base = configured_base_for(path)
      include_callee = callees_needed?

      # Pre-scan: build the file's router wiring (mounts, sub-mounts,
      # constructor prefixes) and resolve compile-time macro variables used
      # in controller references. Cheap substring gates skip the PCRE2 scan
      # on the vast majority of lines. The file's own wiring wins over the
      # project's, so two files that each name a local router `api` keep
      # their own prefixes.
      wiring = Wiring.new
      project_wiring = @project_wiring[project_key_for(path)]?
      macro_vars = {} of String => String
      # Router names bound so far. Constants come from the whole project;
      # locals and instance variables bind at their `Kemal::Router.new`
      # line and unbind when reassigned to anything else.
      routers = Set(String).new
      project_wiring.try &.prefixes.each_key { |name| routers << name }

      lines.each do |line|
        read_router_wiring(line, wiring)
        if include_callee && line.includes?("{{") && (match = line.match(MACRO_VAR_PATTERN))
          macro_vars[match[1]] = match[2]
        end
      end

      # Main scan with namespace stack
      namespace_stack = [] of NamedTuple(prefix: String, indent: Int32, router_var: String)
      # {endpoint index, route path, further prefixes, line}
      extra_mounts = [] of Tuple(Int32, String, Array(String), Int32)
      last_endpoint : Endpoint? = nil
      param_lines = crystal_param_lines(lines)

      lines.each_with_index do |line, index|
        bind_router_name(line, routers)

        # Collect public folder / serve_static info (used by post-pass)
        if line.matches?(SERVE_STATIC_DISABLED_RE)
          @static_disabled_bases << file_base
        end

        if line.includes?("public_folder")
          begin
            split = line.split("public_folder")

            if split.size > 1
              match_data = split[1].match(/[=\(]\s*['"]?(.*?)['"]?\s*[\),]/)
              public_folder = if match_data && match_data[1]?
                                match_data[1].strip
                              else
                                split[1].gsub("(", "").gsub(")", "").gsub(" ", "").gsub("\"", "").gsub("'", "")
                              end

              unless public_folder.empty?
                entry = {file_base, public_folder}
                @public_folders << entry unless @public_folders.includes?(entry)
              end
            end
          rescue
          end
        end

        # Check for namespace open
        if match = line.match(NAMESPACE_PATTERN)
          indent = match[1].size
          router_var = match[2]? || ""
          prefix = match[3]
          namespace_stack << {prefix: prefix, indent: indent, router_var: router_var}
          next
        end

        # Check for end that closes a namespace
        unless namespace_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            if end_indent == namespace_stack.last[:indent]
              namespace_stack.pop
              next
            end
          end
        end

        # Parse endpoint
        endpoint = line_to_endpoint(line)
        receiver = ""
        if endpoint.method.empty? && !routers.empty?
          endpoint, receiver = router_line_to_endpoint(line, routers)
        end
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          # Build full path with namespace prefixes and mount path
          route_path = endpoint.url
          full_path = route_path

          unless namespace_stack.empty?
            # Combine all namespace prefixes
            ns_prefix = ""
            namespace_stack.each do |ns|
              ns_prefix = Noir::URLPath.join(ns_prefix, ns[:prefix])
            end
            full_path = Noir::URLPath.join(ns_prefix, route_path)
          end

          # Router prefix: the `router.get` receiver's, else that of the
          # router whose namespace block encloses a bare `get`. A router
          # mounted at several paths serves the route under each of them.
          router_var = receiver.presence || namespace_stack.first?.try(&.[:router_var]) || ""
          prefixes = router_var.empty? ? [""] : router_prefixes(router_var, wiring, project_wiring)
          endpoint.url = Noir::URLPath.join(prefixes.first, full_path)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          attach_route_callees(endpoint, lines, index, path, macro_vars) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
          if prefixes.size > 1
            extra_mounts << {endpoints.size - 1, full_path, prefixes[1..], index + 1}
          end
        end

        # Parse params
        param = line_to_param(param_lines[index])
        unless param.name.empty?
          if le = last_endpoint
            unless le.method.empty?
              le.push_param(param)
            end
          end
        end
      end

      # Copies for a router's other mounts, made after the scan so each
      # carries the params read below its route, in arrays of its own.
      extra_mounts.each do |endpoint_index, route_path, prefixes, line|
        original = endpoints[endpoint_index]
        prefixes.each do |prefix|
          copy = original
          copy.url = Noir::URLPath.join(prefix, route_path)
          copy.params = original.params.dup
          copy.callees = original.callees.dup
          copy.tags = original.tags.dup
          copy.details = Details.new(PathInfo.new(path, line))
          endpoints << copy
        end
      end

      endpoints
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String, macro_vars : Hash(String, String))
      # Preferred source: the inline `do … end` route block.
      if route_body = extract_crystal_do_block(lines, index)
        body, body_start_line = route_body
        callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_crystal_callees(endpoint, callees)
        return
      end

      # Fallback: `get "/path", Controller, :action` dispatches to a handler
      # in another file — resolve it through the cross-file action index.
      if target = extract_route_target(substitute_macro_vars(lines[index], macro_vars))
        controller, action = target
        if callees = resolve_action_callees(@action_index, controller, action, configured_base_for(path))
          attach_crystal_callees(endpoint, callees)
        end
      end
    end

    private def extract_route_target(line : String) : Tuple(String, String)?
      if match = line.match(/\b(?:get|post|put|delete|patch|head|options|ws|query)\s+['"][^'"]+['"]\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*,\s*:(\w+)/)
        {match[1], match[2]}
      end
    end

    private def substitute_macro_vars(line : String, macro_vars : Hash(String, String)) : String
      return line if macro_vars.empty? || !line.includes?("{{")
      line.gsub(/\{\{\s*(\w+)\s*\}\}/) { |whole| macro_vars[$~[1]]? || whole }
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # Most source lines never touch params; bail before the chain of
      # includes?/split probes when none of the accessor prefixes appear.
      return Param.new("", "", "") unless content.includes?("env.") || content.includes?("cookies.")

      if content.includes? "env.params.query["
        param = content.split("env.params.query[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "env.params.json["
        param = content.split("env.params.json[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "json")
      end

      if content.includes? "env.params.body["
        param = content.split("env.params.body[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      if content.includes? "env.request.headers["
        param = content.split("env.request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "env.request.cookies["
        param = content.split("env.request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      if content.includes? "cookies.get_raw("
        param = content.split("cookies.get_raw(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      Param.new("", "", "")
    end

    # Kemal's `query` route DSL (RFC 10008, kemalcr/kemal#769) is
    # Kemal-specific, unlike `get`/`post`/etc. which the shared engine's
    # SIMPLE_ROUTE_RE already covers for every Crystal analyzer (Amber,
    # Lucky). It's stitched in via `match_crystal_simple_route(..., extra:)`
    # instead of touching that shared pattern, mirroring Lucky's TRACE
    # extra route. The same `(?:^|[^.\w])` lead-in that keeps `before_get`
    # / `after_get` from matching `get` also keeps `before_query` /
    # `after_query` filters from matching here — they must not emit
    # endpoints.
    QUERY_ROUTE_PATTERN = /(?:^|[^.\w])query\s*(?:\(\s*)?['"](.+?)['"]/
    KEMAL_EXTRA_ROUTES  = [{"QUERY", QUERY_ROUTE_PATTERN}] of Tuple(String, Regex)

    private def bind_router_name(line : String, routers : Set(String)) : Nil
      return unless line.includes?('=')
      if line.includes?("Kemal::Router") && (match = line.match(ROUTER_NEW_PATTERN))
        routers << match[1]
      elsif !routers.empty? && !line.matches?(PARAM_DEFAULTS_LINE) &&
            (match = Noir::CrystalCalleeExtractor.strip_comment(line).match(ASSIGN_PATTERN))
        routers.delete(match[1])
      end
    end

    # `router.get "/x"` where `router` is one of `routers`, trying every
    # `x.verb "..."` on the line. Returns the endpoint (empty when nothing
    # matches) and the receiver. Kemal registers `sse` as a GET route.
    def router_line_to_endpoint(content : String, routers : Set(String)) : Tuple(Endpoint, String)
      content = Noir::CrystalCalleeExtractor.strip_comment(content)
      if content.includes?('.')
        content.scan(ROUTER_ROUTE_PATTERN) do |match|
          next unless routers.includes?(match[1])
          verb = match[2]
          endpoint = Endpoint.new(normalize_crystal_interpolation(match[3]), verb.in?("ws", "sse") ? "GET" : verb.upcase)
          endpoint.protocol = "ws" if verb == "ws"
          return {endpoint, match[1]}
        end
      end
      {Endpoint.new("", ""), ""}
    end

    def line_to_endpoint(content : String) : Endpoint
      # Shared engine helper: precompiled per-verb patterns + includes?
      # gates. Replaces 8 sequential unguarded .scan calls per source line.
      match_crystal_simple_route(
        Noir::CrystalCalleeExtractor.strip_comment(content),
        extra: KEMAL_EXTRA_ROUTES
      )
    end
  end
end
