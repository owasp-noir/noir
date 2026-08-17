require "../../engines/javascript_engine"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  class Nuxtjs < JavascriptEngine
    analyzer_for "js_nuxtjs"

    EXTENSIONS = [".js", ".ts", ".mjs", ".mts"]

    def analyze
      # Route candidates paired with the Nuxt app root they came from. A
      # monorepo can hold several Nuxt apps under one scan base, and each
      # app's `server/` tree is its own routing table: `apps/admin/…/auth.ts`
      # and `apps/site/…/auth.ts` are two handlers, not one file seen twice.
      # Collecting first and folding afterwards (see `fold_route_candidates`)
      # keeps the outcome independent of which fiber finished first.
      candidates = [] of Tuple(String, Endpoint)
      mutex = Mutex.new
      include_callee = callees_needed?

      parallel_file_scan(EXTENSIONS) do |path|
        # Focus on server/api and server/routes directories for Nuxt 3
        next unless path.includes?("/server/api/") || path.includes?("/server/routes/")
        # Scan-base-relative, never absolute: a `test/` or `__tests__/`
        # directory ABOVE the scan base is not this project's test tree.
        relative = base_relative_path(path)
        # Skip `*.test.ts` / `*.spec.ts` siblings — they don't
        # define Nuxt event handlers, just exercise neighbors.
        next if relative.includes?(".test.") || relative.includes?(".spec.")
        # Skip mini-Nuxt fixtures used to test the framework itself.
        # nuxt/nuxt parks 18 phantom endpoints under
        # `test/fixtures/<scenario>/server/api/` — each fixture is a
        # full Nuxt project the test suite spins up, but none of the
        # routes serve real traffic.
        next if relative.includes?("/test/fixtures/") || relative.includes?("/tests/fixtures/")
        next if relative.includes?("/__tests__/") || relative.includes?("/__mocks__/")
        analyze_nuxt_file(path, candidates, mutex, include_callee)
      end

      fold_route_candidates(candidates)
    end

    private def analyze_nuxt_file(path : String, candidates : Array(Tuple(String, Endpoint)), mutex : Mutex, include_callee : Bool)
      # Extract endpoint from file path
      # server/api/hello.ts -> /api/hello
      # server/api/users/[id].ts -> /api/users/:id
      # server/api/users.get.ts -> /api/users (GET only)
      # server/routes/custom.ts -> /custom

      # Scan-base-relative, never absolute: `String#index` takes the
      # FIRST occurrence, so a same-named directory above the scan base
      # won outright and the derived URL changed with the checkout path.
      scoped = base_relative_path(path)
      relative_path = scoped
      base_path_idx = scoped.index("/server/api/")
      is_api_route = true

      if base_path_idx.nil?
        base_path_idx = scoped.index("/server/routes/")
        is_api_route = false
      end

      return if base_path_idx.nil?

      # Everything above `/server/api/` or `/server/routes/` is the Nuxt app
      # root — empty when the scan base *is* the app. It keys the dedup in
      # `fold_route_candidates` and nothing else: an app root is a filesystem
      # location, not a URL prefix. Nitro mounts each app's `server/` tree at
      # that app's own base, so `apps/admin/server/routes/auth.ts` is served as
      # `/auth`, and prefixing the directory (`/apps/admin/auth`) would invent
      # a URL no deployment answers.
      app_root = scoped[0...base_path_idx]

      # Get the path after /server/api/ or /server/routes/
      if is_api_route
        relative_path = scoped[(base_path_idx + "/server/api/".size)..-1]
      else
        relative_path = scoped[(base_path_idx + "/server/routes/".size)..-1]
      end

      # Remove file extension
      relative_path = strip_extension(relative_path)

      # Check for HTTP method-specific files (e.g., users.get.ts)
      http_methods = ["get", "post", "put", "delete", "patch", "head", "options"]
      specific_method = nil

      http_methods.each do |method|
        if relative_path.ends_with?(".#{method}")
          specific_method = method.upcase
          relative_path = relative_path[0..-(method.size + 2)]
          break
        end
      end

      # Convert Nuxt dynamic route segments:
      #   [id] -> :id, [...slug] / [[...slug]] -> :slug
      relative_path = convert_nuxt_segments(relative_path)

      # Build the URL
      url = if is_api_route
              "/api/#{relative_path}"
            else
              "/#{relative_path}"
            end

      # Clean up double slashes
      url = url.gsub("//", "/")

      # Handle index routes
      url = url.gsub(/\/index$/, "")
      url = "/" if url.empty?

      # Determine HTTP methods. With a method-suffixed file name
      # (`users.get.ts`) Nuxt only handles that verb. Without one
      # the file's `defineEventHandler` runs for any incoming
      # method, so emit a single `ANY` endpoint instead of seven
      # near-duplicate rows — matching how Echo/Mux/etc. surface
      # method-agnostic registrations.
      methods = specific_method ? [specific_method] : ["ANY"]

      # Read file content to extract parameters
      begin
        content = read_file_content(path)
        sanitized = Noir::JSRouteExtractor.strip_js_comments(content)
        callees = include_callee ? Noir::JSCalleeExtractor.callees_for_default_event_handler(content, path, language: javascript_source_language(path)) : [] of Noir::JSCalleeExtractor::Entry

        methods.each do |method|
          endpoint = Endpoint.new(url, method)
          details = Details.new(PathInfo.new(path, 1))
          endpoint.details = details

          # Extract path parameters from URL
          url.scan(/:(\w+)/) do |m|
            if m.size > 0
              param = Param.new(m[1], "", "path")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == m[1] && p.param_type == "path" }
            end
          end

          # Extract query parameters from getQuery or useQuery
          # Pattern 1: Direct access - getQuery(event).param
          sanitized.scan(/(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)\.(\w+)/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          end
          sanitized.scan(/(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "query")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
          end
          sanitized.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*(?:await\s+)?(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
            extract_destructure_params(m[1]).each do |param_name|
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Pattern 2: Variable assignment - const query = getQuery(event); query.param
          sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:getQuery|useQuery|getValidatedQuery)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |var_match|
            query_var = var_match[1]
            sanitized.scan(cached_regex("nuxtjs:query_dot:#{query_var}") { /#{Regex.escape(query_var)}\.(\w+)/ }) do |m|
              param_name = m[1]
              # Skip common non-parameter properties like 'toString', 'valueOf', etc.
              next if ["toString", "valueOf", "constructor"].includes?(param_name)
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
            sanitized.scan(cached_regex("nuxtjs:query_bracket:#{query_var}") { /#{Regex.escape(query_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |m|
              param_name = m[1]
              param = Param.new(param_name, "", "query")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
            end
          end

          # Extract body parameters from readBody
          if sanitized.includes?("readBody") || sanitized.includes?("readValidatedBody")
            # Try to extract body field access patterns
            sanitized.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*(?:await\s+)?(?:readBody|readValidatedBody)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
              extract_destructure_params(m[1]).each do |param_name|
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
            end
            body_vars = ["body", "data"]
            sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*(?:await\s+)?(?:readBody|readValidatedBody)\s*\(\s*event(?:\s*,[\s\S]*?)?\s*\)/) do |m|
              body_vars << m[1] unless body_vars.includes?(m[1])
            end
            body_vars.each do |body_var|
              sanitized.scan(cached_regex("nuxtjs:var_dot:#{body_var}") { /\b#{Regex.escape(body_var)}\.(\w+)/ }) do |m|
                param_name = m[1]
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
              sanitized.scan(cached_regex("nuxtjs:var_bracket:#{body_var}") { /\b#{Regex.escape(body_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |m|
                param_name = m[1]
                param = Param.new(param_name, "", "body")
                endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "body" }
              end
            end
          end

          # Extract header parameters from getHeader or getHeaders
          sanitized.scan(/(?:getHeader|getRequestHeader)\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            header_name = m[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
          end
          sanitized.scan(/getHeaders\s*\(\s*event\s*\)\.(\w+)/) do |m|
            header_name = m[1]
            param = Param.new(header_name, "", "header")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
          end
          sanitized.scan(/(?:const|let|var)\s+(\w+)\s*=\s*getHeaders\s*\(\s*event\s*\)/) do |m|
            headers_var = m[1]
            sanitized.scan(cached_regex("nuxtjs:var_dot:#{headers_var}") { /\b#{Regex.escape(headers_var)}\.(\w+)/ }) do |mm|
              header_name = mm[1]
              param = Param.new(header_name, "", "header")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
            end
            sanitized.scan(cached_regex("nuxtjs:var_bracket:#{headers_var}") { /\b#{Regex.escape(headers_var)}\s*\[\s*['"]([^'"]+)['"]\s*\]/ }) do |mm|
              header_name = mm[1]
              param = Param.new(header_name, "", "header")
              endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
            end
          end

          # Extract cookie parameters from getCookie
          sanitized.scan(/getCookie\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            cookie_name = m[1]
            param = Param.new(cookie_name, "", "cookie")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
          end
          sanitized.scan(/getRouterParam\s*\(\s*event\s*,\s*['"]([^'"]+)['"]/) do |m|
            param_name = m[1]
            param = Param.new(param_name, "", "path")
            endpoint.push_param(param) unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
          end

          attach_js_callees(endpoint, callees) if include_callee

          mutex.synchronize { candidates << {app_root, endpoint} }
        end
      rescue e : Exception
        logger.debug "Error reading file #{path}: #{e.message}"
      end
    end

    # Fold candidates that resolve to the same (app root, URL, method) into one
    # endpoint, merging params, callees and code paths.
    #
    # This used to run inside the scan: the first file to reach the mutex kept
    # the endpoint and every later one was discarded outright, params, callees
    # and code path included. `parallel_file_scan` hands files to N workers, so
    # "first" meant "whichever fiber won", which had two consequences. Within
    # one app, `users.ts` and `users/index.ts` both resolve to `ANY /api/users`
    # and the losing file's params vanished — and since the loser never reached
    # the optimizer, the deterministic sort there never saw it, so `-f json`
    # differed between runs of the same scan. Across apps in a monorepo, one
    # `auth.ts` erased the other's route entirely.
    #
    # Folding after the scan over a sorted list makes the merge order — and so
    # the emitted `code_paths` and `params` order — depend only on the source
    # tree. Duplicates that survive as separate app roots still carry the same
    # URL, which the optimizer merges by its own documented rules.
    private def fold_route_candidates(candidates : Array(Tuple(String, Endpoint))) : Array(Endpoint)
      ordered = candidates.sort_by do |candidate|
        app_root, endpoint = candidate
        code_path = endpoint.details.code_paths.first?
        {app_root, endpoint.url, endpoint.method, code_path.try(&.path) || "", code_path.try(&.line) || -1}
      end

      result = [] of Endpoint
      seen = {} of Tuple(String, String, String) => Int32

      ordered.each do |candidate|
        app_root, endpoint = candidate
        key = {app_root, endpoint.url, endpoint.method}

        if existing_idx = seen[key]?
          # `Endpoint` is a struct, so `result[existing_idx]` hands back a copy.
          # `push_param` / `push_callee` / `add_path` mutate arrays, which are
          # references and would survive on their own, but write the copy back
          # so any future scalar merge here lands too.
          merged = result[existing_idx]
          endpoint.params.each { |param| merged.push_param(param) }
          endpoint.callees.each { |callee| merged.push_callee(callee) }
          # `Details#add_path` does not dedup, unlike its neighbours.
          endpoint.details.code_paths.each do |code_path|
            merged.details.add_path(code_path) unless merged.details.code_paths.any? { |existing| existing == code_path }
          end
          result[existing_idx] = merged
        else
          seen[key] = result.size
          result << endpoint
        end
      end

      result
    end

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_nuxt_segments(path : String) : String
      path.split("/").map do |segment|
        if m = segment.match(/^\[\[\.\.\.(\w+)\]\]$/)
          ":#{m[1]}"
        elsif m = segment.match(/^\[\.\.\.(\w+)\]$/)
          ":#{m[1]}"
        elsif m = segment.match(/^\[(\w+)\]$/)
          ":#{m[1]}"
        else
          segment
        end
      end.join("/")
    end

    private def extract_destructure_params(destructure : String) : Array(String)
      return [] of String if destructure.includes?("{") || destructure.includes?("(") ||
                             destructure.includes?("<")

      destructure.split(",").map do |part|
        clean = part.split("=").first.strip
        clean = clean.lchop("...").strip
        clean = clean.split(":").first.strip if clean.includes?(":")
        clean = clean[1..-2] if clean.size >= 2 &&
                                ((clean.starts_with?("'") && clean.ends_with?("'")) ||
                                (clean.starts_with?("\"") && clean.ends_with?("\"")))
        clean
      end.select(&.match(/^[A-Za-z_$][\w$-]*$/))
    end
  end
end
