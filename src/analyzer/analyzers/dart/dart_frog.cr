require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # Dart Frog is a filesystem-routed framework. Routes live under
  # `routes/` and the URL is derived from the directory layout:
  #
  #   routes/index.dart                 → /
  #   routes/about.dart                 → /about
  #   routes/users/index.dart           → /users
  #   routes/users/[id].dart            → /users/{id}
  #   routes/users/[id]/posts.dart      → /users/{id}/posts
  #
  # Each route file exports an `onRequest(RequestContext, ...)` handler.
  # Method dispatch happens inside that handler — typically a switch on
  # `context.request.method` against `HttpMethod.<verb>` constants. We
  # surface the verbs we can see referenced in the file and fall back
  # to the standard set when the file looks like a catch-all (no
  # explicit `HttpMethod.*` references).
  #
  # `_middleware.dart` and other underscore-prefixed Dart files are
  # framework plumbing — not user-facing routes — and skipped.
  class DartFrog < Analyzer
    HTTP_METHOD_MAP = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
    }

    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    # Every Dart Frog route file exports an `onRequest` handler — either a
    # function (`Response onRequest(...)`, `Future<Response> onRequest(...)`)
    # or the assignment form (`Handler onRequest = ...`). A `.dart` file
    # under a `routes/` directory that lacks it is not a server route. This
    # matters for full-stack monorepos, where a Flutter client commonly
    # keeps its UI navigation under `lib/.../routes/` — those widget files
    # must not be reported as HTTP endpoints.
    ON_REQUEST_HANDLER_REGEX = /\bonRequest\s*[(=]/

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile) — precompile the fixed verb probes once
    # at load time instead of per handler file.
    HTTP_METHOD_PATTERNS = HTTP_METHOD_MAP.map do |dart_name, verb|
      {verb, /HttpMethod\.#{dart_name}\b/}
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      result = [] of Endpoint
      mutex = Mutex.new

      begin
        files = get_files_by_extension(".dart")

        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")

          # Dart Frog mirrors the route tree under `test/routes/`; those
          # are mock handlers exercised by `dart test`, never live routes.
          next if Helper.test_path?(path, base_paths)

          idx = path.index("/routes/")
          next if idx.nil?

          relative = path[(idx + "/routes/".size)..-1]
          leaf = File.basename(relative)
          next if leaf.starts_with?("_") # `_middleware.dart` and other plumbing

          url = url_for(relative)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          # Only files exporting an `onRequest` handler are Dart Frog
          # routes; skip a Flutter client's `routes/` UI files and any
          # other non-route `.dart` that happens to live under `routes/`.
          next unless content.matches?(ON_REQUEST_HANDLER_REGEX)

          # A `dart_frog_web_socket` route upgrades an HTTP GET; it does
          # not serve the other verbs, so narrow it to GET (rather than the
          # fall-back verb set) and mark the protocol as WebSocket.
          websocket = websocket_route?(content)
          methods = websocket ? ["GET"] : detect_methods(content)
          callees = include_callee ? callees_for_on_request(content, path) : [] of Noir::DartCalleeExtractor::Entry
          mutex.synchronize do
            methods.each do |verb|
              result << build_endpoint(url, verb, path, callees, websocket)
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    # A route file whose handler upgrades to a WebSocket. `webSocketHandler`
    # is the `package:dart_frog_web_socket` entry point.
    private def websocket_route?(content : String) : Bool
      content.includes?("webSocketHandler")
    end

    private def build_endpoint(url : String,
                               verb : String,
                               path : String,
                               callees : Array(Noir::DartCalleeExtractor::Entry) = [] of Noir::DartCalleeExtractor::Entry,
                               websocket : Bool = false) : Endpoint
      endpoint = Endpoint.new(url, verb)
      endpoint.protocol = "ws" if websocket
      endpoint.details = Details.new(PathInfo.new(path, 1))
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    private def callees_for_on_request(content : String, path : String) : Array(Noir::DartCalleeExtractor::Entry)
      content.scan(/\bonRequest\s*\(/) do |match|
        # match.begin is a CHAR index; the extractor scans by BYTE offset.
        match_start = (match.begin(0).try { |i| content.char_index_to_byte_index(i) }) || 0
        open_paren = Noir::DartCalleeExtractor.find_next_code_char(content, '(', match_start)
        next unless open_paren

        close_paren = Noir::DartCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
        next unless close_paren

        body_info = Noir::DartCalleeExtractor.extract_body_after(content, close_paren + 1)
        next unless body_info

        body, body_start, _ = body_info
        start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
        return Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
      end

      # Assignment form: `Handler onRequest = sharedHandler;` (or
      # `= fromShelfHandler(router);`). The handler reference itself is
      # the most useful callee — without this it would be lost entirely.
      if m = content.match(/\bonRequest\s*=\s*([^;]+);/)
        rhs = m[1].strip
        line = Noir::DartCalleeExtractor.line_number_for(content, (m.begin(0).try { |i| content.char_index_to_byte_index(i) }) || 0)
        return assignment_callees(rhs, path, line)
      end

      [] of Noir::DartCalleeExtractor::Entry
    end

    # A bare (possibly dotted) handler reference assigned to `onRequest`.
    HANDLER_REFERENCE_REGEX = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*\z/

    private def assignment_callees(rhs : String, path : String, line : Int32) : Array(Noir::DartCalleeExtractor::Entry)
      return [{rhs, path, line}] of Noir::DartCalleeExtractor::Entry if rhs.matches?(HANDLER_REFERENCE_REGEX)
      Noir::DartCalleeExtractor.callees_for_body(rhs, path, line)
    end

    # Filesystem path → URL pattern. Drops the `.dart` extension,
    # collapses `/index` into the parent, and translates `[id]`
    # to `{id}`.
    private def url_for(relative : String) : String
      stripped = relative.ends_with?(".dart") ? relative[0..-".dart".size - 1] : relative
      segments = stripped.split("/").reject(&.empty?).map { |seg| convert_segment(seg) }
      url = "/" + segments.join("/")
      url = url.sub(/\/index$/, "")
      url = "/" if url.empty?
      url
    end

    private def convert_segment(seg : String) : String
      # Catch-all segment, e.g. `[...slug]` matches one or more path
      # segments. Surface as `{slug}` so the dynamic part is at least
      # captured as a path param even though the framework binds it
      # to a list.
      if m = seg.match(/^\[\.\.\.(\w+)\]$/)
        return "{#{m[1]}}"
      end
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    # Matches `case HttpMethod.<verb>:` clauses inside a method switch.
    CASE_METHOD_REGEX = /\bcase\s+HttpMethod\.([a-z]+)\s*:/
    # A clause body that rejects the verb: `methodNotAllowed`,
    # `MethodNotAllowedResponse()`, or a literal `405` status code passed
    # positionally (`Response(405)`) or by name (`statusCode: 405`). We
    # deliberately avoid a bare `405` so an unrelated `{'code': 405}` in a
    # real handler body can't be mistaken for a rejection.
    METHOD_NOT_ALLOWED_REGEX = /methodNotAllowed|MethodNotAllowed|statusCode\s*:\s*405|\(\s*405\b/

    private def detect_methods(content : String) : Array(String)
      cleaned = Helper.strip_comments(content)

      verbs = [] of String
      HTTP_METHOD_PATTERNS.each do |verb, method_pattern|
        # Dart Frog exposes verbs as `HttpMethod.<lowercase>` constants.
        # Both `==` comparison and `case`/`switch` patterns reach here.
        verbs << verb if cleaned.matches?(method_pattern)
      end
      return FALLBACK_METHODS if verbs.empty?

      # `onRequest` is invoked for every verb, so handlers commonly list
      # the verbs they *don't* support in fall-through `case` clauses that
      # return `methodNotAllowed`. Those are not real endpoints — drop
      # them so we don't over-report.
      rejected = rejected_verbs(cleaned)
      kept = verbs.reject { |v| rejected.includes?(v) }
      kept.empty? ? verbs.uniq : kept.uniq
    end

    # Walk `case HttpMethod.X:` clauses in order, coalescing empty
    # fall-through cases into the group that shares their handler body.
    # Any group whose body resolves to a `methodNotAllowed`/405 response
    # contributes its verbs to the rejected set.
    private def rejected_verbs(cleaned : String) : Set(String)
      rejected = Set(String).new
      clauses = [] of {verb: String, match_begin: Int32, body_start: Int32}
      cleaned.scan(CASE_METHOD_REGEX) do |m|
        verb = HTTP_METHOD_MAP[m[1]]?
        next unless verb
        match_begin = m.begin(0)
        body_start = m.end(0)
        next unless match_begin && body_start
        clauses << {verb: verb, match_begin: match_begin, body_start: body_start}
      end

      pending = [] of String
      clauses.each_with_index do |clause, idx|
        pending << clause[:verb]
        # Bound at the *next clause's* `case` keyword (not its body) so an
        # empty fall-through case isn't credited with the following
        # `case ...:` text and mistaken for a real handler body.
        limit = idx + 1 < clauses.size ? clauses[idx + 1][:match_begin] : cleaned.size
        body = clause_body(cleaned, clause[:body_start], limit)
        next if body.strip.empty? # empty case falls through to the next

        if body.matches?(METHOD_NOT_ALLOWED_REGEX)
          pending.each { |v| rejected << v }
        end
        pending.clear
      end

      rejected
    end

    # The handler body for a `case` clause runs until the next clause or
    # the closing brace of the switch — whichever comes first. We bound
    # at the earliest of a `}`, a `case`, or a `default` keyword so the
    # last enumerated method-case can't sweep in a trailing `default:`
    # arm (whose `405`/`methodNotAllowed` would wrongly tar the case).
    CLAUSE_BOUNDARY_REGEX = /\}|\bcase\b|\bdefault\b/

    private def clause_body(cleaned : String, start : Int32, limit : Int32) : String
      slice = cleaned[start...limit]
      if m = slice.match(CLAUSE_BOUNDARY_REGEX)
        cut = m.begin(0)
        return slice[0...cut] if cut
      end
      slice
    end
  end
end
