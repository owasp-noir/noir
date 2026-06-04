require "../../engines/go_engine"

module Analyzer::Go
  class Gin < GoEngine
    IMPORT_MARKER = "github.com/gin-gonic/gin"

    # Shared read-only fallback for directories with no resolved
    # router-builder prefixes (never mutated).
    EMPTY_BUILDER_PREFIXES = Hash(String, Set(String)).new

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution. Built
      # once per analyze() so each per-file callee pass only does an
      # O(1) lookup into `package_function_bodies` rather than re-
      # walking every sibling source file.
      package_function_bodies = collect_package_function_bodies(file_contents)
      # Cross-file router-builder prefix resolution: `{dir => {builder_fn
      # => set(call-site prefixes)}}`. Resolves the canonical gin layout
      # where `func addXRoutes(rg *gin.RouterGroup)` helpers are called
      # from a central function with a versioned group (`addUserRoutes(
      # router.Group("/v1"))`). The prefix lives at the call site, so it
      # must be grafted onto the helper's routes.
      builder_prefixes_by_dir = resolve_router_builder_prefixes(file_contents, package_groups)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)
                  if File.exists?(path)
                    content = file_contents[path]? || read_file_content(path)
                    next unless content.includes?(IMPORT_MARKER)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass: harvest every verb route with its
                    # group-resolved path in one go. Indexed by line so the
                    # line loop below can attribute body params (Query/PostForm
                    # /GetHeader/Cookie) to the most recently declared route —
                    # matching the legacy `last_endpoint` semantics.
                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))

                    # Router-builder expansion: graft call-site prefixes onto
                    # the routes of `func addXRoutes(rg *gin.RouterGroup)`
                    # helpers DEFINED in this file. Only "case b" helpers are
                    # expanded — those whose group parameter name is NOT
                    # already a key in the package group map. ("Case a" helpers
                    # whose parameter name happens to match a caller's group
                    # variable, e.g. both named `v1`, are already resolved by
                    # the whole-file pass below, so they're left untouched to
                    # keep their params/callees.) Expanded helpers' bodies are
                    # suppressed in the whole-file pass to avoid emitting the
                    # prefix-less variant alongside the corrected one.
                    dir = File.dirname(path)
                    dir_builder_prefixes = builder_prefixes_by_dir[dir]? || EMPTY_BUILDER_PREFIXES
                    expand_builders = [] of Tuple(String, Noir::TreeSitterGoRouteExtractor::RouterBuilder, Set(String))
                    suppress_ranges = [] of Range(Int32, Int32)
                    if content.includes?("*gin.RouterGroup")
                      Noir::TreeSitterGoRouteExtractor.collect_router_group_builders(content).each do |fn, rb|
                        pset = dir_builder_prefixes[fn]?
                        next unless pset && !pset.empty?
                        next if cross_file_groups.has_key?(rb.param)
                        suppress_ranges << (rb.start_row..rb.end_row)
                        expand_builders << {fn, rb, pset}
                      end
                    end

                    # Gin also accepts `r.Handle(method, path, handler)`
                    # alongside the verb shortcuts (`r.GET`, etc.),
                    # so opt into the method-first decoder so those
                    # registrations surface as endpoints too.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups, handle_method: "Handle")
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route in this file.
                    # Inline-closure handlers walk in place; bare
                    # identifier handlers fall through to sibling-file
                    # function bodies via the per-directory map.
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    # Gin uses `r.Static("/url", "./dir")`. Pick these up
                    # in a single tree-sitter pass up front; downstream
                    # `resolve_public_dirs` still expects the legacy hash
                    # shape, so we convert here.
                    Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                      public_dirs << {"static_path" => sp.url_prefix, "file_path" => sp.disk_path}
                    end

                    lines.each_with_index do |line, index|
                      # Skip lines inside an expanded router-builder body — its
                      # routes (and any params) are emitted, with the call-site
                      # prefix applied, by the expansion pass below.
                      next if suppress_ranges.any? { |r| r.includes?(index) }

                      details = Details.new(PathInfo.new(path, index + 1))

                      # Emit endpoints for any verb route that begins on this
                      # line. Gin allows the same verb method name upper/lower
                      # (`r.GET` vs `r.Get`); both are covered by the TS
                      # extractor's HTTP_VERB_METHODS set.
                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          # `r.Any(...)` / `r.All(...)` register one route under
                          # every HTTP method. Fan out so downstream formats
                          # (SARIF / Postman / openapi) get a usable verb per
                          # endpoint instead of a non-HTTP "ANY" string they
                          # can't ingest.
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
                            if entries = callees_by_route[route.line]?
                              entries.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      ["Query", "PostForm", "GetHeader", "Param"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      # Body bindings: `c.BindJSON`, `c.ShouldBindJSON`,
                      # `c.BindXML`, `c.ShouldBindXML`, `c.BindYAML`, etc.
                      # all populate the request body. Emit a single "body"
                      # indicator so downstream consumers know a body is
                      # expected; the bound struct's fields stay opaque
                      # without a deeper static-type pass.
                      if line.matches?(/\.(?:Should)?Bind(?:JSON|XML|YAML|TOML|Query|Header|Uri|With)?\s*\(/)
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
                      end

                      if line.includes?("Cookie(") &&
                         !line.includes?("Header.Get") && !line.includes?("Cookie.Get")
                        match = line.match(/Cookie\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
                      end
                    end

                    # Expansion pass: emit each suppressed router-builder's
                    # routes once per resolved call-site prefix, with the
                    # group parameter bound to that prefix. (A helper called
                    # from two versioned groups — `addPingRoutes(v1)` and
                    # `addPingRoutes(v2)` — yields both `/v1/ping` and
                    # `/v2/ping`.)
                    expand_builders.each do |fn, rb, pset|
                      pset.each do |prefix|
                        Noir::TreeSitterGoRouteExtractor.extract_routes_from_function(
                          content, fn, {rb.param => prefix}, handle_method: "Handle"
                        ).each do |route|
                          rdetails = Details.new(PathInfo.new(path, route.line + 1))
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            result << Endpoint.new(route.path, verb, rdetails)
                          end
                        end
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      resolve_public_dirs(public_dirs)

      result
    end

    # Builds `{dir => {builder_fn => set(prefixes)}}` for the package by
    # (1) collecting every `func F(rg *gin.RouterGroup)` helper across the
    # directory's files and (2) resolving each call site `F(arg)` to the
    # prefix `arg` denotes via the directory group map. A helper called
    # with several different groups accumulates each prefix.
    private def resolve_router_builder_prefixes(file_contents : Hash(String, String),
                                                package_groups : Hash(String, Hash(String, String))) : Hash(String, Hash(String, Set(String)))
      result = Hash(String, Hash(String, Set(String))).new
      files_by_dir = Hash(String, Array(String)).new
      file_contents.each_key { |p| (files_by_dir[File.dirname(p)] ||= [] of String) << p }

      files_by_dir.each do |dir, paths|
        builders = Set(String).new
        paths.each do |p|
          content = file_contents[p]?
          next unless content
          next unless content.includes?("*gin.RouterGroup")
          Noir::TreeSitterGoRouteExtractor.collect_router_group_builders(content).each_key { |fn| builders << fn }
        end
        next if builders.empty?

        group_map = package_groups[dir]? || Hash(String, String).new
        prefixes = Hash(String, Set(String)).new
        paths.each do |p|
          content = file_contents[p]?
          next unless content
          Noir::TreeSitterGoRouteExtractor.collect_router_builder_callsites(content, builders).each do |fn, arg|
            if prefix = group_map[arg]?
              (prefixes[fn] ||= Set(String).new) << prefix
            end
          end
        end
        result[dir] = prefixes unless prefixes.empty?
      end

      result
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("Query(")
        param_type = "query"
      end
      if line.includes?("PostForm(")
        param_type = "form"
      end
      if line.includes?("GetHeader(")
        param_type = "header"
      end
      # `c.Param("id")` — Gin path variable accessor. The optimizer
      # also derives `:id` path params from the URL pattern, but
      # surfacing the accessor lets us catch handlers whose route
      # path was resolved cross-file and avoids depending on the
      # optimizer pass for direct-analyzer consumers.
      if line.includes?(".Param(")
        param_type = "path"
      end

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          if line.includes?("DefaultQuery") || line.includes?("DefaultPostForm")
            param_name = second[0].split(",")[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          else
            param_name = second[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          end

          return rtn
        end
      end

      Param.new("", "", "")
    end
  end
end
