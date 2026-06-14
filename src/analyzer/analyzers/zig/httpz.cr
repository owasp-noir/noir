require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"
require "../../../utils/url_path"

module Analyzer::Zig
  # http.zig (httpz) registers routes on a router object:
  #
  #   router.get("/api/user/:id", getUser, .{});
  #   router.post("/api/users", createUser, .{});
  #   router.all("/*", notFound, .{});
  #   router.method("TEA", "/", teaList, .{});
  #
  # Prefixed groups compose: `var admin = router.group("/admin", .{});`
  # followed by `admin.get("/users", …)` yields `/admin/users`. The handler
  # is the second argument; its function body supplies the callees.
  class Httpz < Analyzer
    VERBS       = %w[get post put delete head patch trace options connect all]
    VERB_METHOD = {
      "get" => "GET", "post" => "POST", "put" => "PUT", "delete" => "DELETE",
      "head" => "HEAD", "patch" => "PATCH", "trace" => "TRACE",
      "options" => "OPTIONS", "connect" => "CONNECT", "all" => "GET",
    }

    GROUP_RE = /(?:var|const)\s+(\w+)\s*=\s*(\w+)\s*\.\s*group\s*\(\s*"([^"]*)"/
    # The handler is the 2nd argument. It can be a plain/qualified identifier
    # (`getUser`, `Users.list`) or a `@"…"` quoted identifier — Zig spells a
    # reserved word used as a name that way, so `router.get("/error", @"error")`
    # is idiomatic. The `@"…"` alternative keeps that form from being dropped.
    ROUTE_RE  = /(\w+)\s*\.\s*(get|post|put|delete|head|patch|trace|options|connect|all)\s*\(\s*"(\/[^"]*)"\s*,\s*(@"[^"]*"|[A-Za-z_][\w.]*)/
    METHOD_RE = /(\w+)\s*\.\s*method\s*\(\s*"([^"]*)"\s*,\s*"(\/[^"]*)"\s*,\s*(@"[^"]*"|[A-Za-z_][\w.]*)/

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next unless path.ends_with?(".zig")
        next if Noir::ZigCalleeExtractor.vendored_framework_path?(path)
        content = read_file_content(path)
        # Route-bearing files don't always reference `httpz` literally — a
        # common layout registers routes in a helper `fn group(router: *Foo)`
        # whose file only imports an app-local `Router` alias (book-store's
        # `api/category.zig`). Gate on a cheap routing signal (a `/…` string
        # argument, or a `.group(` call) instead of the framework name so
        # those files are still scanned. The analyzer only runs at all when
        # the project is already detected as httpz.
        next unless content.includes?("(\"/") || content.includes?(".group(")
        process_file(path, content, include_callee)
      end

      @result
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      bodies = include_callee ? Noir::ZigCalleeExtractor.function_bodies(content, path) : {} of String => Noir::ZigCalleeExtractor::FunctionBody
      # Routes registered inside `test { … }` blocks are test fixtures (and, in
      # an httpz framework source vendored as a loose file, its own self-tests),
      # not runtime endpoints.
      test_blocks = Noir::ZigCalleeExtractor.test_block_ranges(Noir::ZigCalleeExtractor.strip_non_code(content))

      group_prefixes = resolve_group_prefixes(text)

      text.scan(ROUTE_RE) do |m|
        offset = m.begin(0) || 0
        next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
        receiver = m[1]
        verb = m[2]
        route = m[3]
        handler = m[4]
        prefix = group_prefixes[receiver]? || ""
        url = Noir::URLPath.join(prefix, route)
        emit(path, text, offset, url, VERB_METHOD[verb], handler, bodies, include_callee)
      end

      text.scan(METHOD_RE) do |m|
        offset = m.begin(0) || 0
        next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
        receiver = m[1]
        method = m[2].upcase
        route = m[3]
        handler = m[4]
        prefix = group_prefixes[receiver]? || ""
        url = Noir::URLPath.join(prefix, route)
        emit(path, text, offset, url, method, handler, bodies, include_callee)
      end
    end

    # Build groupVar => composed-prefix, resolving nested groups
    # (`v1 = admin.group("/v1", …)` inherits `/admin`).
    private def resolve_group_prefixes(text : String) : Hash(String, String)
      raw = {} of String => Tuple(String, String) # var => {parent, prefix}
      text.scan(GROUP_RE) do |m|
        raw[m[1]] = {m[2], m[3]}
      end

      resolved = {} of String => String
      raw.each_key do |var|
        resolved[var] = compose_prefix(var, raw, [] of String)
      end
      resolved
    end

    private def compose_prefix(var : String, raw : Hash(String, Tuple(String, String)), seen : Array(String)) : String
      entry = raw[var]?
      return "" if entry.nil?
      return entry[1] if seen.includes?(var) # cycle guard
      parent, prefix = entry
      parent_prefix = raw.has_key?(parent) ? compose_prefix(parent, raw, seen + [var]) : ""
      Noir::URLPath.join(parent_prefix, prefix)
    end

    private def emit(path, text, offset, url, method, handler, bodies, include_callee)
      params = extract_path_params(url)
      line = Noir::ZigCalleeExtractor.line_at(text.chars, offset)
      details = Details.new(PathInfo.new(path, line))
      endpoint = Endpoint.new(url, method, params, details)

      if include_callee
        name = handler.includes?('.') ? handler.split('.').last : handler
        if body = bodies[name]?
          callees = Noir::ZigCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
          Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        end
      end

      @result << endpoint
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_]\w*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end
  end
end
