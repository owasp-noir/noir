require "../../engines/crystal_engine"
require "../../../utils/url_path"

module Analyzer::Crystal
  class Marten < CrystalEngine
    alias HandlerActionKey = Tuple(String, String, String)
    @handler_callees = Hash(HandlerActionKey, Array(Noir::CrystalCalleeExtractor::Entry)).new

    # One `path "…", Target[, name: …]` line inside a routing map. `target`
    # is either a handler const (leaf route) or another map const (mount).
    record MartenMapEntry, path : String, target : String, file : String, line : Int32

    # A `Marten::Routing::Map.draw do … end` block: the application's main
    # map (`Marten.routes.draw`, fqn `__main__`) or a named sub-map
    # (`Auth::ROUTES = Marten::Routing::Map.draw`, fqn `Auth::ROUTES`).
    record MartenRouteMap, fqn : String, entries : Array(MartenMapEntry)

    MAIN_MAP_FQN = "__main__"

    def analyze
      collect_public_dir_endpoints
      @handler_callees = include_callee? ? collect_handler_callees : Hash(HandlerActionKey, Array(Noir::CrystalCalleeExtractor::Entry)).new

      # Marten splits routing across files: a main `Marten.routes.draw`
      # mounts per-app sub-maps (`path "/auth", Auth::ROUTES`) whose own
      # `path` declarations live in `src/apps/*/routes.cr`. Parse every map
      # up front so mounts can compose their prefix onto the sub-map's
      # routes (`/auth` + `/signin` => `/auth/signin`) instead of emitting
      # the sub-routes bare and the mount line as a junk endpoint.
      main_maps = [] of MartenRouteMap
      named_maps = Hash(String, MartenRouteMap).new
      mutex = Mutex.new

      parallel_file_scan do |path|
        local_main = [] of MartenRouteMap
        local_named = Hash(String, MartenRouteMap).new
        parse_route_maps_in_file(read_source_lines(path), path, local_main, local_named)
        next if local_main.empty? && local_named.empty?
        mutex.synchronize do
          main_maps.concat(local_main)
          local_named.each { |fqn, map| named_maps[fqn] = map }
        end
      end

      emit_maps(main_maps, named_maps)
      result
    end

    # Map parsing replaces the per-file walk; `analyze` drives everything.
    def analyze_file(path : String) : Array(Endpoint)
      [] of Endpoint
    end

    # Walk a file, collecting each routing map (main or named) it declares.
    private def parse_route_maps_in_file(lines : Array(String),
                                         path : String,
                                         main_maps : Array(MartenRouteMap),
                                         named_maps : Hash(String, MartenRouteMap)) : Nil
      module_stack = [] of NamedTuple(name: String, indent: Int32)
      index = 0

      while index < lines.size
        line = Noir::CrystalCalleeExtractor.strip_comment(lines[index])
        content = line.lstrip
        if content.empty?
          index += 1
          next
        end
        indent = line.size - content.size

        while !module_stack.empty? && module_stack.last[:indent] >= indent
          module_stack.pop
        end

        if mod = content.match(/^(?:abstract\s+)?module\s+([A-Z]\w*(?:::[A-Z]\w*)*)/)
          module_stack << {name: mod[1], indent: indent}
          index += 1
          next
        end

        if content.matches?(/^Marten\.routes\.draw\b/)
          entries, index = parse_draw_block(lines, index, indent, path)
          main_maps << MartenRouteMap.new(MAIN_MAP_FQN, entries)
          next
        end

        if const = content.match(/^([A-Z]\w*)\s*=\s*Marten::Routing::Map\.draw\b/)
          scope = module_stack.map(&.[:name]).join("::")
          fqn = scope.empty? ? const[1] : "#{scope}::#{const[1]}"
          entries, index = parse_draw_block(lines, index, indent, path)
          named_maps[fqn] = MartenRouteMap.new(fqn, entries)
          next
        end

        index += 1
      end
    end

    # Collect the `path` entries of a `…draw do … end` block opened at
    # `start_index`. Returns the entries and the index just past the
    # block's closing `end`. Routes nested in an `if Marten.env.…` guard
    # sit at a deeper indent and are still collected; the block closes at
    # the first `end` back at (or shallower than) the opener's column.
    private def parse_draw_block(lines : Array(String),
                                 start_index : Int32,
                                 opener_indent : Int32,
                                 path : String) : Tuple(Array(MartenMapEntry), Int32)
      entries = [] of MartenMapEntry
      index = start_index + 1

      while index < lines.size
        line = Noir::CrystalCalleeExtractor.strip_comment(lines[index])
        content = line.lstrip
        if content.empty?
          index += 1
          next
        end
        indent = line.size - content.size

        if indent <= opener_indent && content.matches?(/^end\b/)
          index += 1
          break
        end

        if route = content.match(/^path\s+['"](.*?)['"]\s*,\s*((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)/)
          route_path = normalize_crystal_interpolation(route[1])
          entries << MartenMapEntry.new(route_path, route[2], path, index + 1)
        end

        index += 1
      end

      {entries, index}
    end

    # Emit endpoints by walking each main map and composing mount prefixes
    # onto sub-map routes. A sub-map referenced by no map (orphan) is still
    # emitted bare so its routes are never lost.
    private def emit_maps(main_maps : Array(MartenRouteMap),
                          named_maps : Hash(String, MartenRouteMap)) : Nil
      referenced = Set(String).new
      (main_maps + named_maps.values).each do |map|
        map.entries.each do |entry|
          if target = resolve_map(entry.target, named_maps)
            referenced << target.fqn
          end
        end
      end

      main_maps.each { |map| walk_map(map, "", named_maps, Set(String).new) }
      named_maps.each do |fqn, map|
        next if referenced.includes?(fqn)
        walk_map(map, "", named_maps, Set(String).new)
      end
    end

    private def walk_map(map : MartenRouteMap,
                         prefix : String,
                         named_maps : Hash(String, MartenRouteMap),
                         visiting : Set(String)) : Nil
      return if visiting.includes?(map.fqn)
      visiting = visiting.dup
      visiting << map.fqn

      map.entries.each do |entry|
        if target = resolve_map(entry.target, named_maps)
          walk_map(target, Noir::URLPath.join(prefix, entry.path), named_maps, visiting)
        else
          emit_leaf(entry, prefix)
        end
      end
    end

    private def resolve_map(target : String,
                            named_maps : Hash(String, MartenRouteMap)) : MartenRouteMap?
      normalized = normalize_absolute_crystal_const(target)
      named_maps[normalized]? || named_maps.values.find(&.fqn.ends_with?("::#{normalized}"))
    end

    private def emit_leaf(entry : MartenMapEntry, prefix : String) : Nil
      url = Noir::URLPath.join(prefix, entry.path)
      return unless valid_crystal_route_path?(url)

      endpoint = Endpoint.new(url, "GET")
      endpoint.details = Details.new(PathInfo.new(entry.file, entry.line))

      if include_callee?
        handler = normalize_absolute_crystal_const(entry.target)
        if callees = @handler_callees[handler_action_key(configured_base_for(entry.file), handler, "get")]?
          attach_crystal_callees(endpoint, callees)
        end
      end

      @result << endpoint
    end

    private def collect_public_dir_endpoints
      each_public_file do |file|
        # Extract the path after "/public/" regardless of depth
        if file =~ /\/public\/(.*)/
          relative_path = $1
          @result << Endpoint.new("/#{relative_path}", "GET")
        end
      end
    rescue e
      logger.debug e
    end

    private def include_callee? : Bool
      any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
    end

    private def read_source_lines(path : String) : Array(String)
      mask_crystal_heredocs(read_file_content(path).lines)
    end

    private def collect_handler_callees : Hash(HandlerActionKey, Array(Noir::CrystalCalleeExtractor::Entry))
      actions = Hash(HandlerActionKey, Array(Noir::CrystalCalleeExtractor::Entry)).new

      get_files_by_extension(".cr").each do |path|
        next if File.directory?(path)
        next unless File.exists?(path)
        next if crystal_dependency_path?(path)

        collect_handler_callees_from_lines(read_source_lines(path), path, actions)
      rescue e
        logger.debug "Error collecting Marten handler callees from #{path}: #{e}"
      end

      actions
    end

    private def collect_handler_callees_from_lines(lines : Array(String),
                                                   path : String,
                                                   actions : Hash(HandlerActionKey, Array(Noir::CrystalCalleeExtractor::Entry)))
      scope_stack = [] of Tuple(String, String)
      base = configured_base_for(path)

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line).strip

        if stripped == "end" || stripped.starts_with?("end ")
          scope_stack.pop? unless scope_stack.empty?
          next
        end

        if module_match = stripped.match(/^module\s+((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"module", qualified_crystal_const(module_match[1], scope_stack)} unless stripped.match(/\bend\b/)
          next
        end

        if class_match = stripped.match(/^class\s+((?:::)?[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          scope_stack << {"class", qualified_crystal_const(class_match[1], scope_stack)} unless stripped.match(/\bend\b/)
          next
        end

        if (current_class = current_direct_crystal_class(scope_stack)) &&
           (def_match = stripped.match(/^(?:(?:private|protected)\s+)?def\s+(get)\b/))
          method_body = extract_crystal_def_block(lines, index)
          if method_body
            body, body_start_line = method_body
            callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
            actions[handler_action_key(base, current_class, def_match[1])] = callees
          end
          scope_stack << {"block", ""} unless stripped.match(/\bend\b/)
          next
        end

        crystal_do_block_open_delta(stripped).times do
          scope_stack << {"block", ""}
        end
      end
    end

    private def qualified_crystal_const(name : String, scope_stack : Array(Tuple(String, String))) : String
      return normalize_absolute_crystal_const(name) if name.starts_with?("::")

      prefix = current_crystal_const_scope(scope_stack)
      prefix.empty? ? name : "#{prefix}::#{name}"
    end

    private def current_crystal_const_scope(scope_stack : Array(Tuple(String, String))) : String
      scope_stack.reverse_each do |kind, name|
        return name if kind == "module" || kind == "class"
      end

      ""
    end

    private def current_direct_crystal_class(scope_stack : Array(Tuple(String, String))) : String?
      scope_stack.reverse_each do |kind, name|
        return name if kind == "class"
      end

      nil
    end

    private def normalize_absolute_crystal_const(name : String) : String
      name.starts_with?("::") ? name[2, name.size - 2] : name
    end

    private def handler_action_key(base : String, handler : String, action : String) : HandlerActionKey
      {base, handler, action}
    end
  end
end
