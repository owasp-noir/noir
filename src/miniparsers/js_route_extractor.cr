require "../models/endpoint"
require "../miniparsers/js_callee_extractor"
require "../miniparsers/js_handler_resolver"
require "../minilexers/js_lexer"
require "../miniparsers/js_parser"
require "../miniparsers/import_graph"
require "../models/code_locator"
require "../utils/url_path"
require "../utils/js_literal_scanner"
require "../analyzer/analyzers/javascript/express_constants"
require "../utils/text_file"

module Noir
  # JSRouteExtractor provides a unified interface for extracting routes from JavaScript files
  class JSRouteExtractor
    # JSLexer route positions are CHAR indices, but every String op keyed
    # by a char index (`[]`, `index(str, offset)`, `MatchData#begin`) walks
    # from byte 0 once a file holds one non-ASCII char, and
    # `index(String, offset)` does so even on ASCII. Done per route that was
    # quadratic in the route count. Convert each position once here and work
    # in bytes, so per-route cost stays proportional to the route's own text.
    class ByteOffsets
      getter content : String

      def initialize(@content : String)
        bytes = content.to_slice
        @newlines = [] of Int32
        i = 0
        while nl = bytes.index('\n'.ord.to_u8, i)
          @newlines << nl
          i = nl + 1
        end
        @char_starts = nil.as(Array(Int32)?)
        unless content.bytesize == content.size
          starts = Array(Int32).new(content.size + 1)
          reader = Char::Reader.new(content)
          while reader.has_next?
            starts << reader.pos
            reader.next_char
          end
          starts << content.bytesize
          @char_starts = starts
        end
      end

      # Byte offset of CHAR index `char_pos`.
      def byte(char_pos : Int32) : Int32
        if starts = @char_starts
          starts[char_pos.clamp(0, starts.size - 1)]
        else
          char_pos.clamp(0, @content.bytesize)
        end
      end

      # 1-based line of a byte offset.
      def line(byte_pos : Int32) : Int32
        (@newlines.bsearch_index { |nl| nl >= byte_pos } || @newlines.size) + 1
      end

      # Up to `max` bytes from `start`, shortened to end on a char boundary.
      def window(start : Int32, max : Int32) : String
        stop = Math.min(start + max, @content.bytesize)
        while stop > start && stop < @content.bytesize && (@content.to_unsafe[stop] & 0xC0) == 0x80
          stop -= 1
        end
        @content.byte_slice(start, stop - start)
      end
    end

    def self.extract_routes(file_path : String,
                            content : String? = nil,
                            debug : Bool = false,
                            *,
                            include_callees : Bool = false,
                            route_callees : Hash(String, Array(JSCalleeExtractor::Entry))? = nil,
                            unwrap_guards : Bool = false) : Array(Endpoint)
      return [] of Endpoint unless File.exists?(file_path)

      begin
        content = content || Noir::TextFile.read(file_path)

        # Cheap pre-filter: every shape the JSParser knows about ends
        # in a verb call (`x.get(`, `.post(`, ...), a Fastify/Restify
        # `.route(` registration, or an Express-style mount (`.use(`).
        # Skip the lex+parse pass entirely for files that contain none
        # of these — UI components, fixtures, helpers, third-party JS
        # bundles — so a large frontend tree doesn't pay parser cost
        # for files that can't host an endpoint.
        return [] of Endpoint unless route_call_candidate?(content)
        # Skip minified/bundled assets (webpack/rollup/esbuild output,
        # `*.min.js`, generated single-line blobs). They never define
        # hand-written routes, and tokenizing a multi-megabyte bundle is
        # the dominant scan cost when a small Express/Fastify/... server
        # lives inside a large frontend monorepo — a single ~1.6 MB
        # `public/lib/*.js` bundle can keep `parse_routes` busy for
        # seconds (issue #1903). Unlike `test_stub_only?`, this skip is
        # intentionally NOT re-enabled by an HTTP-server import: a
        # minified single line is never the canonical hand-written
        # server even if it bundles express's own source.
        if minified_content?(content)
          STDERR.puts "Skipping #{file_path} for route extraction (minified/bundled asset)" if debug
          return [] of Endpoint
        end
        # Skip mock-server fixtures (pretender/mirage/MSW/nock).
        # Their `server.get(...)` / handler-builder calls match the
        # parser's route shape but are not real registrations; on
        # Ember-based projects (Discourse, etc.) these files account
        # for the bulk of analysis time and produce only false
        # positives.
        if test_stub_only?(file_path, content)
          STDERR.puts "Skipping #{file_path} for route extraction (test-stub/non-server marker)" if debug
          return [] of Endpoint
        end
        # Handler bodies are read with regexes below (`req.header('x')`,
        # `this.route('GET', '/p')`), so a comment inside a call would hide
        # the literal. Blanking keeps every line and column.
        content = strip_js_comments(content)
        # `${BASE_URL}/items` or `BASE_URL + '/items'`, `BASE_URL` imported
        # from `./config`.
        constants = content.includes?("${") || content.includes?('+') ? file_string_constants(file_path, content) : nil
        parser = JSParser.new(content, this_receiver_ok: content_matches?(content, SERVER_EVIDENCE_MARKER), constants: constants)
        route_patterns = parser.parse_routes

        if debug && parser.hit_max_iterations?
          STDERR.puts "Warning: Maximum iterations reached in JS parser, parsing may be incomplete"
        end
        if debug && parser.mount_prefixes_capped?
          STDERR.puts "#{file_path}: router prefixes capped at #{MAX_MOUNT_PREFIXES} per router"
        end

        # No route patterns means the rest of this method has nothing
        # to emit — every downstream step (function_ranges build,
        # internal-mount scan, prefix propagation) exists to attribute
        # prefixes to routes the parser already found.
        return [] of Endpoint if route_patterns.empty?

        # Only now: the callee table is a tree-sitter parse of the whole
        # file, and it is only ever consulted for the routes found above.
        callees_by_route = if include_callees
                             route_callees || JSCalleeExtractor.callees_for_routes(content, file_path)
                           else
                             {} of String => Array(JSCalleeExtractor::Entry)
                           end

        # Check if this file has a router prefix from cross-file mounting
        locator = CodeLocator.instance

        # Normalize file path to absolute path for consistent lookup
        absolute_file_path = Noir::PathScope.expand(file_path)
        lookup_key = Analyzer::Javascript::ExpressConstants.file_key(absolute_file_path)
        # Use all() since routers can be mounted at multiple prefixes
        file_prefixes = locator.all(lookup_key)

        offsets = ByteOffsets.new(content)

        # Build function ranges to support function-scoped router prefixes.
        # Ranges and route positions below are BYTE offsets (see ByteOffsets).
        function_ranges = [] of Tuple(String, Int32, Int32)
        function_names = Set(String).new
        function_patterns = {
          /function\s+(\w+)\s*\(/                                       => :function,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?function\b/     => :function,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\([^)]*\)\s*=>/ => :arrow,
          /(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\w+\s*=>/       => :arrow,
        }
        function_patterns.each do |pattern, kind|
          content.scan(pattern) do |m|
            next unless m.size >= 2
            func_name = m[1]
            match_start = m.byte_begin(0)

            open_brace_idx = if kind == :arrow
                               arrow_idx = content.byte_index("=>", match_start)
                               next unless arrow_idx
                               content.byte_index('{', arrow_idx + 2)
                             else
                               param_start = content.byte_index('(', match_start)
                               next unless param_start
                               param_end = JSLiteralScanner.find_matching_paren_at_byte(content, param_start) || param_start
                               content.byte_index('{', param_end + 1)
                             end

            next unless open_brace_idx
            close_brace_idx = JSLiteralScanner.find_matching_brace_at_byte(content, open_brace_idx)
            next unless close_brace_idx
            function_ranges << {func_name, open_brace_idx, close_brace_idx}
            function_names.add(func_name)
          end
        end

        # Build internal mount relationships: parent function -> child function with prefix
        internal_mounts = [] of Tuple(String, String, String)
        function_ranges.each do |func_name, start_idx, end_idx|
          body = content.byte_slice(start_idx, end_idx - start_idx + 1)
          body.scan(/\b\w+\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(\w+)\s*(?:\(\s*\))?/) do |m|
            if m.size >= 3
              prefix = m[1]
              child_func = m[2]
              if function_names.includes?(child_func)
                internal_mounts << {func_name, child_func, prefix}
              end
            end
          end

          body.scan(/\b\w+\.register\s*\(\s*(\w+)\s*,\s*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |m|
            if m.size >= 3
              child_func = m[1]
              prefix = m[2]
              if function_names.includes?(child_func)
                internal_mounts << {func_name, child_func, prefix}
              end
            end
          end
        end

        # Track inline anonymous Fastify plugins:
        #   fastify.register(function (instance, options, done) { ... }, { prefix: '/x' })
        #   fastify.register((instance, options) => { ... }, { prefix: '/x' })
        #
        # These callbacks have no stable function name, so they can't reuse the
        # function-scoped CodeLocator path. Keep their body ranges local and apply
        # the prefix directly to routes whose start position falls inside.
        anonymous_register_ranges = [] of Tuple(Int32, Int32, String)
        anonymous_register_patterns = [
          /\b\w+\.register\s*\(\s*(?:async\s+)?function\s*[\w$]*\s*\([^)]*\)\s*\{/,
          /\b\w+\.register\s*\(\s*(?:async\s+)?\([^)]*\)\s*=>\s*\{/,
          /\b\w+\.register\s*\(\s*(?:async\s+)?\w+\s*=>\s*\{/,
        ]
        seen_anonymous_registers = Set(String).new

        anonymous_register_patterns.each do |register_pattern|
          content.scan(register_pattern) do |m|
            match_start = m.byte_begin(0)

            register_paren_idx = content.byte_index('(', match_start)
            open_brace_idx = content.byte_index('{', match_start)
            next unless register_paren_idx && open_brace_idx

            close_brace_idx = JSLiteralScanner.find_matching_brace_at_byte(content, open_brace_idx)
            close_paren_idx = JSLiteralScanner.find_matching_paren_at_byte(content, register_paren_idx)
            next unless close_brace_idx && close_paren_idx
            next if close_brace_idx >= close_paren_idx

            trailer = content.byte_slice(close_brace_idx + 1, close_paren_idx - close_brace_idx - 1)

            prefix_match = trailer.match(/prefix\s*:\s*['"]([^'"]+)['"]/)
            next unless prefix_match

            prefix = prefix_match[1]
            key = "#{open_brace_idx}:#{close_brace_idx}:#{prefix}"
            next if seen_anonymous_registers.includes?(key)

            anonymous_register_ranges << {open_brace_idx, close_brace_idx, prefix}
            seen_anonymous_registers.add(key)
          end
        end

        # Seed function-specific prefixes from CodeLocator
        prefixes_by_function = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
        function_names.each do |func_name|
          func_key = Analyzer::Javascript::ExpressConstants.function_key(absolute_file_path, func_name)
          # The `else` branch this replaces called `get(func_key)` — reading
          # the single-value map for a key only ever `push`ed to. It could
          # never return anything, and `get`'s old `rescue → ""` hid that.
          # Under typed keys it does not compile.
          locator.all(func_key).each do |prefix|
            prefixes_by_function[func_name] << prefix unless prefix.empty?
          end
        end

        # Routers imported by name: prefixes recorded under the exported
        # name apply to routes registered on the local binding.
        prefixes_by_binding = Hash(String, Array(String)).new
        export_bindings(content).each do |local, exported_names|
          list = exported_names.flat_map do |exported|
            locator.all(Analyzer::Javascript::ExpressConstants.function_key(absolute_file_path, exported))
          end.uniq!.reject!(&.empty?)
          prefixes_by_binding[local] = list unless list.empty?
        end

        # Seed same-file Fastify plugin registrations from top-level mounts.
        content.scan(/\b\w+\.register\s*\(\s*(\w+)\s*,\s*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |m|
          next unless m.size >= 3
          func_name = m[1]
          prefix = m[2]
          next unless function_names.includes?(func_name)
          # A plugin registering itself is an internal mount (handled
          # below), not a top-level prefix for the plugin.
          reg_pos = m.byte_begin(0)
          next if function_ranges.any? { |name, open_idx, close_idx| name == func_name && open_idx <= reg_pos <= close_idx }
          prefixes_by_function[func_name] << prefix unless prefixes_by_function[func_name].includes?(prefix)
        end

        # Propagate prefixes through internal mounts; an unprefixed parent
        # mounts at the file's own cross-file prefix.
        if propagate_mount_prefixes(
             internal_mounts.map { |parent, child, mount_prefix| {parent, mount_prefix, child} },
             prefixes_by_function, file_prefixes)
          STDERR.puts "#{file_path}: mount prefixes capped at #{MAX_MOUNT_PREFIXES} per router" if debug
        end

        endpoints = [] of Endpoint
        # How many registrations in this file each last argument ends, for
        # telling a shared renderer from a route's own handler; counted on
        # first need.
        last_step_counts = [] of Hash(String, Int32)
        count_last_steps = Proc(Hash(String, Int32)).new do
          if last_step_counts.empty?
            tally = Hash(String, Int32).new(0)
            route_patterns.each do |pat|
              pat_start = pat.start_pos >= 0 ? offsets.byte(pat.start_pos) : -1
              route_arguments(content, pat_start).last?.try { |last| tally[last.strip] += 1 }
            end
            last_step_counts << tally
          end
          last_step_counts[0]
        end
        route_patterns.each do |pattern|
          start_byte = pattern.start_pos >= 0 ? offsets.byte(pattern.start_pos) : -1
          # Apply cross-file router prefix if present (function-scoped first)
          prefixes = [] of String
          if start_byte >= 0
            # Find all functions containing this route, sorted by span (innermost first)
            containing_functions = [] of Tuple(String, Int32)
            function_ranges.each do |func_name, start_idx, end_idx|
              if start_idx <= start_byte && start_byte <= end_idx
                span = end_idx - start_idx
                containing_functions << {func_name, span}
              end
            end
            containing_functions.sort_by! { |_, span| span }

            # Walk outward through enclosing functions until we find one with prefixes
            containing_functions.each do |func_name, _|
              func_prefixes = prefixes_by_function[func_name]
              unless func_prefixes.empty?
                prefixes = func_prefixes
                break
              end
            end
          end
          if prefixes.empty? && start_byte >= 0
            containing_registers = [] of Tuple(String, Int32)
            anonymous_register_ranges.each do |start_idx, end_idx, prefix|
              if start_idx <= start_byte && start_byte <= end_idx
                containing_registers << {prefix, end_idx - start_idx}
              end
            end
            unless containing_registers.empty?
              # Nested registers compose, outermost first, under the
              # file's own cross-file prefix.
              containing_registers.sort_by! { |_, span| -span }
              anonymous_prefix = containing_registers.reduce("") { |joined, (prefix, _)| URLPath.join(joined, prefix) }
              prefixes = (file_prefixes.empty? ? [""] : file_prefixes).map { |file_prefix| URLPath.join(file_prefix, anonymous_prefix) }
            end
          end
          if prefixes.empty? && start_byte >= 0 && !prefixes_by_binding.empty?
            # Some parser paths report a position inside the receiver token
            # (`usersRouter` at its last char); back up to the token start.
            receiver_start = start_byte
            while receiver_start > 0 && identifier_byte?(content.to_unsafe[receiver_start - 1])
              receiver_start -= 1
            end
            if receiver = offsets.window(receiver_start, 128).match(ROUTE_RECEIVER_RE)
              # A sub-router mounted on the exported router (`router.use(
              # '/comfy', comfy)`) is served under the exported router's
              # cross-file prefix too; the parser already folded the in-file
              # part (`/comfy`) into the route's own path.
              if root = parser.nearest_ancestor(receiver[1]) { |name| prefixes_by_binding.has_key?(name) }
                prefixes = prefixes_by_binding[root]
              end
            end
          end
          if prefixes.empty? && !file_prefixes.empty?
            prefixes = file_prefixes
          end
          prefixes = [""] if prefixes.empty?

          # Normalize HTTP method (e.g., DEL -> DELETE)
          normalized_method = normalize_http_method(pattern.method)

          line_number = start_byte >= 0 ? offsets.line(start_byte) : 1
          route_details = Details.new(PathInfo.new(file_path, line_number))

          # Body/query/header/... params from the handler, read once per
          # route rather than once per prefix and expanded method.
          context = Endpoint.new("", "")
          extract_params_from_context(offsets, pattern, context, file_path)
          step = handler_step(content, start_byte, file_path, offsets, unwrap_guards, count_last_steps)
          handler = step ? named_handler(step[0], content, file_path, unwrap_guards) : nil
          handler_facts = handler ? handler_definition_facts(handler, include_callees) : nil
          handler = nil unless step.nil? || serves?(handler_facts, before_renderer: step[3])
          handler ||= step ? inline_handler(step[0], step[1], content, file_path, unwrap_guards) : nil
          # Only a route that has a handler, named or inline: a guard-only
          # registration (`app.put('/x', security.denyAll())`) has none for
          # its steps to feed.
          chain_callees = if include_callees && step
                            route_args = route_arguments(content, start_byte)
                            if (handler && handler_facts) || (handler && handler.name == "closure") || route_args.last?.try(&.matches?(INLINE_CLOSURE_START_RE))
                              chain_step_callees(route_args[0...step[2]], content, file_path)
                            end
                          end

          # Handle router.all by expanding to all HTTP methods
          prefixes.each do |prefix|
            path_with_prefix = prefix.empty? ? pattern.path : URLPath.join(prefix, pattern.path)
            path_with_prefix = "/" if path_with_prefix.empty?

            if normalized_method == "ALL"
              all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
              all_methods.each do |method|
                endpoint = Endpoint.new(path_with_prefix, method, route_details)

                # Add path parameters detected in the URL
                pattern.params.each do |param|
                  endpoint.push_param(param)
                end

                context.params.each { |param| endpoint.push_param(param) }
                attach_callees(endpoint, callees_by_route, normalized_method, pattern.raw_path, line_number)
                endpoint.handler = handler
                apply_handler_facts(endpoint, handler_facts)
                push_callees(endpoint, chain_callees)

                endpoints << endpoint
              end
            else
              endpoint = Endpoint.new(path_with_prefix, normalized_method, route_details)

              # Add path parameters detected in the URL
              pattern.params.each do |param|
                endpoint.push_param(param)
              end

              context.params.each { |param| endpoint.push_param(param) }
              attach_callees(endpoint, callees_by_route, normalized_method, pattern.raw_path, line_number)
              endpoint.handler = handler
              apply_handler_facts(endpoint, handler_facts)
              push_callees(endpoint, chain_callees)

              endpoints << endpoint
            end
          end
        end

        endpoints
      rescue
        # If parser fails, return empty array
        [] of Endpoint
      end
    end

    # Pre-filter for `extract_routes`: returns false when `content`
    # contains no shape the JS parser knows how to emit (any verb
    # invocation pattern like `.get(`/`.post(`/... or Fastify/Restify
    # `.route(`, plus Express-style mounts `.use(` which feed into the
    # cross-file router prefix table). Matching is millions of times
    # cheaper than tokenizing the file.
    BRACKET_ROUTE_CALL_PATTERN  = /\[\s*['"](?:get|post|put|delete|del|patch|options|head|all|query)['"]\s*\]\s*\(/i
    FLEXIBLE_ROUTE_CALL_PATTERN = /\.(?:\s|\n|\r)*(?:get|post|put|delete|del|patch|options|head|all|query|route|register|use)(?:\s|\n|\r)*\(/i

    # A 22-literal `includes?` pre-pass used to run ahead of these two
    # patterns (`".get("`, `".get ("`, ... for each verb). Every one of
    # those literals is `.` + verb + optional space + `(`, which
    # `FLEXIBLE_ROUTE_CALL_PATTERN` already matches with zero or one
    # whitespace character — so the pre-pass could never change the
    # result, and each miss cost 22 Rabin-Karp walks of the whole file.
    def self.route_call_candidate?(content : String) : Bool
      content.matches?(BRACKET_ROUTE_CALL_PATTERN, options: Noir::TextFile::MATCH_OPTIONS) ||
        content.matches?(FLEXIBLE_ROUTE_CALL_PATTERN, options: Noir::TextFile::MATCH_OPTIONS)
    end

    # Byte length above which a single source line is considered "long".
    # Hand-written JS/TS keeps lines well under this even in dense route
    # tables (noir's own widest fixture line is ~150 bytes); webpack/
    # rollup/esbuild bundles and `*.min.js` assets routinely pack tens of
    # thousands of bytes onto one line, so 5000 leaves a wide margin.
    # NB: the metric is bytes, not characters — a dense single-line
    # non-Latin blob (>=5000 bytes but fewer chars) can trip it, which is
    # acceptable since real route registrations are ASCII verbs/paths.
    MINIFIED_LINE_THRESHOLD = 5000

    # Average bytes-per-line above which a file is considered *dominated*
    # by long lines, i.e. a bundle rather than hand-written source that
    # merely carries one fat literal (a big inline JSON seed, an embedded
    # base64 data URI, a long regex). Real code keeps the average low
    # because it has many short lines around any such literal.
    MINIFIED_AVG_LINE_THRESHOLD = 1000

    # True when `content` looks like a minified/bundled asset rather than
    # hand-written source. Two conditions must BOTH hold so we never drop
    # the routes of a normal file that just happens to carry one long
    # line (issue #1903 review):
    #   1. at least one line reaches MINIFIED_LINE_THRESHOLD bytes, and
    #   2. the *rest* of the file — every code line except that single
    #      fattest one — still averages MINIFIED_AVG_LINE_THRESHOLD bytes
    #      or more, i.e. long lines dominate and newline density is low.
    #
    # Condition (2) deliberately sets aside the longest line and every
    # blank/comment-only line before averaging. Averaging over the *whole*
    # file (the original rule) let one fat literal drag a small module over
    # the threshold: a 13-line Express server carrying a 20 KB
    # `const LOGO = 'data:image/png;base64,…'` line averages ~1.5 KB/line
    # and was classified as a bundle, so all ten of its routes were dropped
    # silently. Dropping the single fattest line barely moves a real
    # bundle's average (it has several enormous lines, or nothing else at
    # all) but collapses such a module's to a few dozen bytes.
    #
    # Blank and comment-only lines are excluded for the same reason in the
    # other direction: the canonical `*.min.js` is one enormous line
    # wrapped in a `/*! license */` banner and a `//# sourceMappingURL=`
    # trailer. Those decorations are not source, so a bundle that carries
    # them must still be recognised as a bundle.
    #
    # A file with no code line left over (a single enormous line, with or
    # without banner/sourcemap decoration) is judged on that line alone —
    # it is the bundle shape by definition.
    #
    # webpack/rollup output and `*.min.js` satisfy both conditions; a route
    # module with a fat inline payload amid real route lines satisfies
    # neither, so its endpoints survive. Skipping such a file is purely a
    # parser optimization — small files lex fast regardless — so there is
    # no need to skip one merely because it embeds a fat literal.
    def self.minified_content?(content : String,
                               line_threshold : Int32 = MINIFIED_LINE_THRESHOLD,
                               avg_threshold : Int32 = MINIFIED_AVG_LINE_THRESHOLD) : Bool
      bytesize = content.bytesize
      # Too small to contain a long-enough line — also skips the scan on
      # the vast majority of source files for free.
      return false if bytesize < line_threshold

      bytes = content.to_slice

      longest = 0
      longest_start = 0
      longest_end = 0
      line_start = 0
      index = 0
      while index < bytesize
        if bytes[index] == 0x0a_u8 # '\n'
          if index - line_start > longest
            longest = index - line_start
            longest_start = line_start
            longest_end = index
          end
          line_start = index + 1
        end
        index += 1
      end
      if bytesize - line_start > longest
        longest = bytesize - line_start
        longest_start = line_start
        longest_end = bytesize
      end

      return false if longest < line_threshold

      # Second pass: average the code lines that are NOT the fattest one.
      # Only files that already cleared the per-line threshold get here, so
      # this rescan runs on a handful of files per project at most.
      rest_bytes = 0
      rest_lines = 0
      line_start = 0
      index = 0
      while index <= bytesize
        if index == bytesize || bytes[index] == 0x0a_u8
          unless line_start == longest_start && index == longest_end
            if code_line?(bytes, line_start, index)
              rest_bytes += index - line_start
              rest_lines += 1
            end
          end
          line_start = index + 1
        end
        index += 1
      end

      return longest >= avg_threshold if rest_lines == 0
      (rest_bytes // rest_lines) >= avg_threshold
    end

    # True when the byte range [`from`, `to`) carries something other than
    # whitespace, a `//` line comment or a `/* … */` block-comment line.
    # Intentionally shallow — it only has to tell a bundle's banner and
    # sourcemap trailer apart from real source lines, not lex JavaScript.
    private def self.code_line?(bytes : Bytes, from : Int32, to : Int32) : Bool
      index = from
      while index < to
        byte = bytes[index]
        break unless byte == 0x20_u8 || byte == 0x09_u8 || byte == 0x0d_u8
        index += 1
      end
      return false if index >= to

      byte = bytes[index]
      return false if byte == 0x2a_u8      # '*' — a block comment's continuation or its `*/`
      if byte == 0x2f_u8 && index + 1 < to # '/'
        following = bytes[index + 1]
        return false if following == 0x2f_u8 || following == 0x2a_u8 # '//' or '/*'
      end
      true
    end

    # Test-fixture libraries whose API mimics route registration:
    # `pretender`/`miragejs` expose `server.get("/x", ...)`, MSW and
    # nock expose handler builders, sinon-via-faker likewise. When
    # these libraries are imported, virtually every route-shaped call
    # in the file is a stub, not a real registration. Substring match
    # is enough — these tokens never appear in production HTTP server
    # source under normal circumstances.
    TEST_STUB_LIBRARY_MARKERS = [
      "pretender",
      "miragejs",
      "ember-cli-mirage",
      "from \"msw\"", "from 'msw'",
      "from \"msw/", "from 'msw/",
      "require(\"msw\")", "require('msw')",
      "from \"nock\"", "from 'nock'",
      "require(\"nock\")", "require('nock')",
      # fetch-mock: the same job as msw/nock for the `fetch` API, and the
      # same call shape — `fetchMock.get('glob:*/api/v1/token/*', body)`.
      # Superset's `setupClientForTest.ts` / `setupSupersetClient.js`
      # registered its glob patterns as Express routes, so the catalog
      # reported `GET /glob:*api/v1/security/csrf_token/*`.
      "from \"fetch-mock\"", "from 'fetch-mock'",
      "from \"fetch-mock/", "from 'fetch-mock/",
      "require(\"fetch-mock\")", "require('fetch-mock')",
      "setupApplicationTest",
      "setupRenderingTest",
      # Cypress: e2e suites use `cy.request(...)` / `cy.get(...)`
      # shaped calls that match the parser's route hint but are
      # test invocations, not registrations.
      "/// <reference types=\"cypress\" />",
      "from \"cypress\"", "from 'cypress'",
      "require(\"cypress\")", "require('cypress')",
      # Playwright: e2e suites use `request.get(...)` / `page.goto`
      # in the same shape.
      "from \"@playwright/test\"", "from '@playwright/test'",
      "from \"playwright\"", "from 'playwright'",
      # supertest: the canonical `request(app).get(...)` test client.
      # Production code never depends on supertest, so its presence is
      # a strong signal the surrounding `.get(`/`.post(` calls are
      # HTTP requests against an app under test, not registrations.
      "from \"supertest\"", "from 'supertest'",
      "require(\"supertest\")", "require('supertest')",
      # axios: the dominant HTTP-client lib for both browser and Node.
      # Files that import axios but don't also import an HTTP-server
      # lib are almost always making outbound calls (`axios.get(url,
      # config)`), not registering routes. Mastodon's
      # `app/javascript/**/*.{ts,tsx,js}` tree alone accounts for ~72
      # phantom Express endpoints from chains like
      # `axios.get('/api/v1/accounts/lookup', { params: {...} })`.
      # The HTTP-server-import exemption (below) keeps real backend
      # files alive — production servers that internally call axios
      # still scan because they also import express/fastify/...
      "from \"axios\"", "from 'axios'",
      "require(\"axios\")", "require('axios')",
      # The rest of the Node.js HTTP-client family. Each is almost
      # exclusively used for outbound calls and never to register
      # routes. Strapi's `purest`-based OAuth provider registry
      # accounts for 6 phantom Koa endpoints (`discord.get('users/
      # @me')` etc.); the others (got, ky, superagent, node-fetch,
      # ofetch, undici, request) crop up in similar shapes across
      # most Node backends.
      "from \"purest\"", "from 'purest'",
      "require(\"purest\")", "require('purest')",
      "from \"got\"", "from 'got'",
      "require(\"got\")", "require('got')",
      "from \"ky\"", "from 'ky'",
      "require(\"ky\")", "require('ky')",
      "from \"superagent\"", "from 'superagent'",
      "require(\"superagent\")", "require('superagent')",
      "from \"node-fetch\"", "from 'node-fetch'",
      "require(\"node-fetch\")", "require('node-fetch')",
      "from \"ofetch\"", "from 'ofetch'",
      "require(\"ofetch\")", "require('ofetch')",
      "from \"undici\"", "from 'undici'",
      "require(\"undici\")", "require('undici')",
      "from \"request\"", "from 'request'",
      "require(\"request\")", "require('request')",
      # Apollo REST data sources. A `class FooAPI extends
      # RESTDataSource` makes *outbound* calls — `this.get('/users')`,
      # `this.post('/orders', body)` — whose verb-DSL shape matches the
      # parser's route hint but registers nothing. Generated BFF data
      # sources under `**DataSource.ts` are the canonical offenders
      # (issue #1903); their only HTTP-server-shaped import is the
      # datasource lib itself, so the server-import exemption below
      # never keeps them alive by mistake.
      "from \"apollo-datasource-rest\"", "from 'apollo-datasource-rest'",
      "require(\"apollo-datasource-rest\")", "require('apollo-datasource-rest')",
      "from \"@apollo/datasource-rest\"", "from '@apollo/datasource-rest'",
      "require(\"@apollo/datasource-rest\")", "require('@apollo/datasource-rest')",
      # Throwaway test HTTP servers (`createTestHttpServer({ defineRoutes(router)
      # { router.post('/x', ...) } })`). msw's `vitest.setup.ts` registered 64
      # routes this way; the library is a devDependency-only test utility.
      "@epic-web/test-server",
      "@open-draft/test-server",
      "create-test-server",
    ]

    # Client-side UI framework imports. A file that imports a browser
    # UI framework (Vue, React, Angular, Svelte, Solid, Preact) and its
    # satellite libs (pinia, vue-router, @vueuse, react-router, ...) is
    # SPA/frontend code, not an HTTP server. Its route-shaped calls are
    # outbound API-client requests against a configured client — e.g.
    # directus's admin app does `api.get(`/users/${userId}`)` where `api`
    # is a wrapped axios instance imported from `@/api`. The existing
    # axios/got/ky markers miss these because the wrapper hides the raw
    # client behind a local module, but the UI-framework import is an
    # unambiguous "this is browser code" signal. directus's admin SPA
    # alone parks ~61 phantom Express endpoints across
    # `app/src/{stores,composables,layouts,...}` this way. Like the
    # test-stub markers, this is gated by the HTTP-server-import
    # exemption below: an SSR entrypoint that imports BOTH vue and
    # express keeps its routes.
    CLIENT_SIDE_FRAMEWORK_MARKERS = [
      "from \"vue\"", "from 'vue'",
      "from \"@vue/", "from '@vue/",
      "from \"vue-router\"", "from 'vue-router'",
      "from \"@vueuse/", "from '@vueuse/",
      "from \"pinia\"", "from 'pinia'",
      "from \"react\"", "from 'react'",
      "from \"react-dom", "from 'react-dom",
      "from \"react-router", "from 'react-router",
      "from \"@angular/", "from '@angular/",
      "from \"svelte\"", "from 'svelte'",
      "from \"svelte/", "from 'svelte/",
      "from \"solid-js", "from 'solid-js",
      "from \"preact\"", "from 'preact'",
      "from \"preact/", "from 'preact/",
      # Single-File-Component imports (`import Foo from './Foo.vue'`). A
      # file that pulls in a `.vue`/`.svelte` component is frontend by
      # construction — a route/module definition file that wires up
      # components and happens to call a wrapped API client. directus's
      # `app/src/modules/**/index.ts` is the canonical case: it imports
      # dozens of `.vue` routes and also fires `api.patch(...)`.
      ".vue\"", ".vue'",
      ".svelte\"", ".svelte'",
      # Browser state, data-fetching and telemetry libraries. Outline's MobX
      # stores import only `mobx` and `@sentry/react` (no `react`), so none
      # of the markers above fired on their `client.post('/users.delete',
      # data)`. k6 is the load-test runtime (`http.post(url, data)`).
      "from \"mobx", "from 'mobx",
      "from \"redux\"", "from 'redux'",
      "from \"react-redux", "from 'react-redux",
      "from \"@reduxjs/", "from '@reduxjs/",
      "from \"zustand", "from 'zustand",
      "from \"swr\"", "from 'swr'",
      "from \"@tanstack/react-query\"", "from '@tanstack/react-query'",
      "from \"@sentry/react\"", "from '@sentry/react'",
      "from \"vuex\"", "from 'vuex'",
      "from \"jquery\"", "from 'jquery'",
      "from \"k6", "from 'k6",
    ]

    # Real HTTP-server library imports. When any of these is present
    # alongside a test-stub marker, the file is doing legitimate
    # server work (e.g., spinning up a test instance of an Express
    # app) and we still want to extract its routes.
    HTTP_SERVER_LIBRARY_MARKERS = [
      "from \"express\"", "from 'express'",
      "require(\"express\")", "require('express')",
      "from \"fastify\"", "from 'fastify'",
      "require(\"fastify\")", "require('fastify')",
      "from \"koa\"", "from 'koa'",
      "require(\"koa\")", "require('koa')",
      "from \"hono\"", "from 'hono'",
      "require(\"hono\")", "require('hono')",
      "from \"restify\"", "from 'restify'",
      "require(\"restify\")", "require('restify')",
      "from \"polka\"", "from 'polka'",
      "from \"h3\"", "from 'h3'",
      "from \"@nestjs/", "from '@nestjs/",
      "from \"@oak/oak\"", "from '@oak/oak'",
      "deno.land/x/oak",
    ]

    # Path-level evidence that a file is a mock-server fixture.
    # Pretender helpers in particular get a `helper`/`this` arg and
    # call `this.get(...)` / `this.post(...)` directly, so they have
    # no library-name imports the content filter can hook on — fall
    # back to the convention-based filename match.
    TEST_STUB_PATH_MARKERS = [
      "-pretender.",  # *-pretender.js / *-pretender.ts
      "-pretenders.", # *-pretenders.js
      ".pretender.",  # *.pretender.js
      "-mirage.",     # *-mirage.js
      ".mirage.",
      "/tests/helpers/", # Ember convention (Discourse)
      "/test/helpers/",
      "/tests/api/",        # Strapi-style integration test bundles
      "/__tests__/",        # Jest convention (n8n, many TS projects)
      "/test/integration/", # supertest-style integration suites
      "/tests/integration/",
      "/test/e2e/",
      "/tests/e2e/",
      "/cypress/", # Cypress e2e tree (Mattermost: e2e-tests/cypress/)
      "/playwright/",
      "/e2e-tests/",
      "/e2e/", # Ghost's `e2e/helpers/services/*` mock servers,
      # Cypress's plain `e2e/` layout
      "/mirage/", # Ember mirage stub-server config trees (Ghost,
      # Discourse legacy admin)
      # Browser-side specs (etherpad's `src/tests/frontend/specs/*.js` run
      # jQuery `$.get(...)` in the page).
      "/tests/frontend/",
      "/test/frontend/",
      # Fixture apps that only the test run loads (Egg/Midway's
      # `test/fixtures/apps/*/app/router.js`). Lenient, so a fixture server
      # that really imports express still scans. Not a bare `/fixtures/`:
      # that is also an ordinary API resource folder.
      "/test/fixtures/",
      "/tests/fixtures/",
      "/__fixtures__/",
      "/__mocks__/", # Jest manual-mock convention used across the
      # TS ecosystem
      # Bundled output: GitHub Action `dist/` blobs, Next.js
      # `.next`, Nuxt `.nuxt`/`.output`, generic `dist/`, `build/`,
      # `coverage/`, `vendor/`. These contain webpacked third-party
      # code where every `.get(`/`.post(` is library noise, not an
      # app route.
      "/dist/",
      "/build/",
      "/.next/",
      "/.nuxt/",
      "/.output/",
      "/coverage/",
      "/vendor/",
      # Rails Webpacker / esbuild / Vite source root. Anything under
      # `app/javascript/` in a Rails app is browser-side code that
      # calls into the backend (`api().get('/x')`, `axios.get('/y')`),
      # never a route registration. Mastodon's repo alone parks ~68
      # phantom Express endpoints across
      # `app/javascript/mastodon/actions/*.js` redux modules. The
      # HTTP-server-import exemption keeps the rare case of a SSR
      # entrypoint that genuinely runs express alive.
      "/app/javascript/",
      # Web-served static root. By framework convention (Next.js, CRA,
      # Vite, Express `express.static('public')`, ...) anything under a
      # `public/` directory is browser-facing static output —
      # webpack/rollup bundles, vendored libs, `*.min.js` — never a
      # route registration. A small Express server inside a monorepo
      # otherwise pays parser cost for every `apps/*/public/lib/*.js`
      # asset (issue #1903). The HTTP-server-import exemption keeps the
      # rare hand-written server script that genuinely imports express.
      "/public/",
    ]

    # Hard test-file markers: when the filename itself follows a
    # ubiquitous test convention, the file practically never
    # defines real routes. Skip these even when the file imports
    # a real HTTP server lib — NestJS e2e tests routinely import
    # `@nestjs/platform-express` for type-only references, and
    # supertest harnesses import the same modules they exercise.
    # The supertest `request(app).get(...)` shape would otherwise
    # ride the HTTP-server-import exemption straight back into the
    # parser.
    TEST_STUB_FILENAME_MARKERS = [
      ".test.",
      ".spec.",
      # tsd / expect-type style type-only test files. fastify's
      # `test/types/*.test-d.ts` suites register sample routes purely
      # to assert their inferred typings — no production endpoints,
      # but the JSParser pre-filter sees the same `app.get(`/`.post(`
      # shapes.
      ".test-d.",
      # tstyche type-test suffix (fastify's `test/types/*.tst.ts`).
      ".tst.",
    ]

    # The hyphen forms are also ordinary English in production router names
    # (`routes/ab-test.js`, `routes/api-spec.js`), so they count as a test
    # only without an HTTP server import, or with a test harness (a supertest
    # suite imports express too). NestJS's `app.e2e-spec.ts` is always a test.
    HYPHEN_TEST_FILENAME_MARKER = Regex.union("-spec.", "-test.")
    E2E_SPEC_FILENAME_MARKER    = "e2e-spec."
    TEST_HARNESS_MARKER         = /\bdescribe\s*\(|\bDeno\.test\s*\(|\bsupertest\b|@nestjs\/testing/

    # A suite file that registers its own throwaway app is a test whatever
    # server library it imports. Line-anchored: `.describe(` is also zod's
    # and Joi's schema annotation in ordinary route files.
    TEST_DIR_MARKER   = %r{/tests?/}
    TEST_SUITE_MARKER = /^[ \t]*(?:describe(?:\.(?:only|skip))?|Deno\.test)\s*\(|\bLab\.script\(/m

    # Deno/mocha-style `foo_test.ts` / `foo_spec.js`. snake_case is ordinary
    # in production names too (`routes/ab_test.js`, `convex/load_test.ts`,
    # `speed_test.js`), so these are a test only when the file holds a suite
    # (`TEST_SUITE_MARKER`) — never on the name alone and never because of an
    # import (a fastify-plugin or router module imports nothing a test would).
    UNDERSCORE_TEST_FILENAME_MARKER = Regex.union("_spec.", "_test.")

    # True when the file's route-shaped calls are almost certainly
    # mock-server stubs (Ember pretender, MSW, nock, ...) rather
    # than real route registrations. Two routes:
    #
    # Path markers strict enough that the HTTP-server-import
    # exemption shouldn't apply: `/e2e/`, `/cypress/`, `/playwright/`,
    # `/__mocks__/`, `/__tests__/`, `/e2e-tests/`, `/mirage/`. Real
    # apps never park production handlers under any of these — even
    # when the harness file imports express to spin up a faked
    # service (Ghost's `e2e/helpers/services/stripe/fake-stripe-server.ts`
    # is the canonical example). Keeping the exemption out of these
    # paths catches the harness fakes without affecting legit
    # backend code.
    STRICT_TEST_PATH_MARKERS = [
      "/e2e/",
      "/cypress/",
      "/playwright/",
      "/__mocks__/",
      "/__tests__/",
      "/e2e-tests/",
      "/mirage/",
    ]

    #   * Filename markers fire unconditionally — `foo.test.ts` is
    #     a test no matter what it imports.
    #   * Strict path markers also fire unconditionally — `e2e/`,
    #     `cypress/`, etc. are dedicated test/mock trees that never
    #     contain production handlers, even when the harness file
    #     imports a server lib.
    #   * Library + the remaining directory markers honor an
    #     exemption — if the file also imports a real HTTP server
    #     lib (express, fastify, ...), keep it so legit test-server
    #     harnesses (e.g. mattermost's `webhook_serve.js`) keep
    #     their routes.
    # `include_client_frameworks` controls whether a client-side UI
    # framework import (Vue/React/...) counts as a skip signal. It must be
    # ON for the verb-DSL extractor (a React/Vue file calling `api.get(...)`
    # is an outbound client call, not a route), but OFF for analyzers whose
    # OWN route definitions live in client-side files — TanStack Router
    # (`createFileRoute`) and tRPC route modules routinely `import { ... }
    # from 'react'`, and skipping them on that basis dropped every such
    # route. The test-stub *library* markers (msw/supertest/...) and path/
    # filename markers still apply in both modes.
    # Precompiled unions of the marker lists above. `Regex.union` escapes
    # every String argument, so each is exactly the `any? includes?` it
    # replaces — but the content lists are long (72 test-stub libraries,
    # 32 client frameworks, 26 server libraries), and every JS/TS file in
    # the tree used to be walked once per literal.
    TEST_STUB_FILENAME_MARKER    = Regex.union(TEST_STUB_FILENAME_MARKERS)
    STRICT_TEST_PATH_MARKER      = Regex.union(STRICT_TEST_PATH_MARKERS)
    TEST_STUB_PATH_MARKER        = Regex.union(TEST_STUB_PATH_MARKERS)
    TEST_STUB_LIBRARY_MARKER     = Regex.union(TEST_STUB_LIBRARY_MARKERS)
    CLIENT_SIDE_FRAMEWORK_MARKER = Regex.union(CLIENT_SIDE_FRAMEWORK_MARKERS)
    HTTP_SERVER_LIBRARY_MARKER   = Regex.union(HTTP_SERVER_LIBRARY_MARKERS)

    # Every marker below names a directory *inside the project*
    # (`__tests__/`, `dist/`, `vendor/`, `public/`, ...), so they are
    # matched on the scan-base-relative path. Matched on the absolute
    # path they also fired on directories ABOVE the base: a checkout
    # under `~/build/` or `~/vendor/` looked like bundled output and
    # every route in it disappeared (the JS fixture tree dropped from
    # 430 endpoints to 394, and to 191 under `__tests__/`).
    def self.test_stub_only?(file_path : String, content : String,
                             include_client_frameworks : Bool = true) : Bool
      relative_path = CodeLocator.instance.base_relative(file_path)
      basename = File.basename(file_path)
      return true if test_file?(basename, relative_path, content)
      has_library = content_matches?(content, TEST_STUB_LIBRARY_MARKER) ||
                    (include_client_frameworks && content_matches?(content, CLIENT_SIDE_FRAMEWORK_MARKER))
      if basename.matches?(HYPHEN_TEST_FILENAME_MARKER)
        return basename.includes?(E2E_SPEC_FILENAME_MARKER) ||
          content_matches?(content, TEST_HARNESS_MARKER) ||
          !content_matches?(content, HTTP_SERVER_LIBRARY_MARKER)
      end
      has_path_marker = relative_path.matches?(TEST_STUB_PATH_MARKER)
      return false unless has_library || has_path_marker
      !content_matches?(content, HTTP_SERVER_LIBRARY_MARKER)
    end

    # Whether the file is a test by its name, a dedicated test tree, or a
    # suite under `test/`/`tests/`, ignoring what it imports. Callers whose
    # frameworks `HTTP_SERVER_LIBRARY_MARKER` does not list (hapi, Elysia)
    # use this instead of `test_stub_only?`, which would let any server
    # import keep a test's routes and drop real routes beside axios/react.
    def self.test_file?(file_path : String, content : String) : Bool
      test_file?(File.basename(file_path), CodeLocator.instance.base_relative(file_path), content)
    end

    private def self.test_file?(basename : String, relative_path : String, content : String) : Bool
      return true if test_named_or_in_test_tree?(basename, relative_path)
      return false unless relative_path.matches?(TEST_DIR_MARKER) || basename.matches?(UNDERSCORE_TEST_FILENAME_MARKER)
      content_matches?(content, TEST_SUITE_MARKER)
    end

    # The content-free half of `test_file?`: a test by its name
    # (`*.test.*`, `*.spec.*`, ...) or inside a dedicated test tree
    # (`__tests__/`, `e2e/`, ...). Shared with `JavascriptEngine#js_test_file?`,
    # which has to decide before it reads the file.
    def self.test_named_or_in_test_tree?(basename : String, relative_path : String) : Bool
      basename.matches?(TEST_STUB_FILENAME_MARKER) || relative_path.matches?(STRICT_TEST_PATH_MARKER)
    end

    # Match against file content, which always came from a
    # `Noir::TextFile.read` (directly or via the detector's cache).
    private def self.content_matches?(content : String, markers : Regex) : Bool
      markers.matches?(content, options: Noir::TextFile::MATCH_OPTIONS)
    end

    # Import markers for the five frameworks whose analyzers call
    # `extract_routes` directly and therefore share its framework-agnostic
    # verb-chaining shape (`.get(`/`.post(`/...). Keyed by the same Symbol
    # each analyzer passes to `other_shared_extractor_framework?` below.
    SHARED_EXTRACTOR_FRAMEWORK_MARKERS = {
      :express => [
        "from \"express\"", "from 'express'",
        "require(\"express\")", "require('express')",
      ],
      :fastify => [
        "from \"fastify\"", "from 'fastify'",
        "require(\"fastify\")", "require('fastify')",
        "from \"fastify-plugin\"", "from 'fastify-plugin'",
        "require(\"fastify-plugin\")", "require('fastify-plugin')",
        "from \"@fastify/", "from '@fastify/",
        "require(\"@fastify/", "require('@fastify/",
      ],
      :koa => [
        "from \"koa\"", "from 'koa'",
        "require(\"koa\")", "require('koa')",
        "from \"koa-router\"", "from 'koa-router'",
        "require(\"koa-router\")", "require('koa-router')",
        "from \"@koa/router\"", "from '@koa/router'",
        "require(\"@koa/router\")", "require('@koa/router')",
      ],
      :hono => [
        "from \"hono\"", "from 'hono'",
        "require(\"hono\")", "require('hono')",
        "from \"hono/", "from 'hono/",
      ],
      :restify => [
        "from \"restify\"", "from 'restify'",
        "require(\"restify\")", "require('restify')",
        "from \"restify-router\"", "from 'restify-router'",
        "require(\"restify-router\")", "require('restify-router')",
      ],
      # Oak is Deno-native and ships no package.json, so its import
      # evidence is the specifier itself: the JSR package (`@oak/oak`,
      # optionally through a bare `jsr:` specifier) or the legacy URL
      # import (`https://deno.land/x/oak@vX.Y.Z/mod.ts`). The bare
      # "deno.land/x/oak" substring covers every versioned/unversioned
      # URL form without needing to enumerate them.
      :oak => [
        "from \"@oak/oak\"", "from '@oak/oak'",
        "from \"jsr:@oak/oak", "from 'jsr:@oak/oak",
        "require(\"@oak/oak\")", "require('@oak/oak')",
        "deno.land/x/oak",
      ],
    }

    # Sibling JS/TS server frameworks that DON'T call `extract_routes`
    # (NestJS uses decorators, Hapi/Elysia/AdonisJS have their own
    # tree-sitter extractors) but whose files are still walked by every
    # JS/TS analyzer's `parallel_file_scan`. These markers are exclusion-
    # only: recognizing "this file belongs to NestJS" keeps Express/
    # Fastify/Koa/Hono/Restify from re-extracting a route-shaped call
    # (an inline example, a raw `app.use()` bridge, ...) out of it.
    OTHER_FRAMEWORK_MARKERS = {
      :nestjs => [
        "from \"@nestjs/", "from '@nestjs/",
        "require(\"@nestjs/", "require('@nestjs/",
      ],
      :hapi => [
        "from \"@hapi/hapi\"", "from '@hapi/hapi'",
        "require(\"@hapi/hapi\")", "require('@hapi/hapi')",
        "from \"hapi\"", "from 'hapi'",
        "require(\"hapi\")", "require('hapi')",
      ],
      :elysia => [
        "from \"elysia\"", "from 'elysia'",
        "require(\"elysia\")", "require('elysia')",
      ],
      :adonisjs => [
        "from \"@adonisjs/", "from '@adonisjs/",
        "require(\"@adonisjs/", "require('@adonisjs/",
        "from \"@ioc:Adonis/", "from '@ioc:Adonis/",
      ],
    }

    # True when `content` carries definitive import evidence of a
    # *different* shared-extractor (or sibling) framework than
    # `framework`, with no evidence of `framework` itself. Guards the main
    # `extract_routes` call in Express/Fastify/Koa/Hono/Restify's
    # analyzers: a file that only imports 'hono' should never be
    # re-attributed to js_express just because its `.get()/.post()`
    # chaining looks the same as Express's (issue #2368) — whichever
    # analyzer runs over it first no longer matters once #2367 made the
    # dedup tiebreak deterministic, because the over-matching analyzer
    # never produces a competing endpoint in the first place.
    #
    # Files with no shared-extractor/sibling import at all (a router
    # module that only receives `app`/`router` as a bare parameter, with
    # no import in that file) return false here and fall through to the
    # existing, permissive whole-tree scan — there's no import to
    # disambiguate on, so narrowing further is left as follow-up scope
    # (a confirmed package.json dependency or cross-file mount signal
    # would be needed to resolve those).
    # Per-framework precompiled unions of the two tables above: the
    # framework's own import markers, and the markers of every *other*
    # shared-extractor framework. Together with the sibling union this
    # turns the up-to-44-literal `includes?` walk below into three
    # matches. Five analyzers call this on every JS/TS file, so the old
    # shape scanned some trees over 200 times per file.
    OWN_EXTRACTOR_MARKER = SHARED_EXTRACTOR_FRAMEWORK_MARKERS
      .transform_values { |markers| Regex.union(markers) }

    OTHER_EXTRACTOR_MARKER = SHARED_EXTRACTOR_FRAMEWORK_MARKERS.keys.to_h do |framework|
      others = SHARED_EXTRACTOR_FRAMEWORK_MARKERS
        .reject { |other, _| other == framework }
        .values
        .flatten
      {framework, Regex.union(others)}
    end

    SIBLING_FRAMEWORK_MARKER = Regex.union(OTHER_FRAMEWORK_MARKERS.values.flatten)

    # Any import of a server framework the shared extractor serves. A file
    # without one reads `this.post(...)` as an outbound client call, not a
    # route (`JSParser#initialize`).
    SERVER_EVIDENCE_MARKER = Regex.union(HTTP_SERVER_LIBRARY_MARKERS + SHARED_EXTRACTOR_FRAMEWORK_MARKERS.values.flatten)

    # Constructors that build an HTTP *client*. `client.get('/todo', cb)` is
    # the same call shape as a route registration, so a client module reads as
    # a server to the shared extractor: the Express analyzer reported
    # `GET /todo` and `DELETE /todo/example` out of a restify-clients module
    # that only calls a remote API.
    #
    # The restify analyzer already refused these; the check belongs here so
    # every framework sharing the extractor gets it. It is deliberately
    # limited to client *constructors* rather than client package names —
    # a genuine route file may well `require('axios')` to call downstream
    # services, and gating on that would drop its routes.
    HTTP_CLIENT_CONSTRUCTOR_MARKER = Regex.union(
      "restify-clients", "createJSONClient(", "createStringClient(", "createHttpClient("
    )

    # A `@fastify/autoload` plugin module names no framework at all — it
    # receives the instance as a parameter:
    #
    #     export default async function (fastify) {
    #       fastify.get('/status', handler)
    #     }
    #
    # so no import marker fires and the shared extractor happily reads those
    # registrations for whichever framework asked. Express reported `/status`
    # and `/go` out of the fastify autoload fixture, without the `autoPrefix`
    # the Fastify analyzer applies. The receiver name is the only evidence in
    # the file, and `fastify` is unambiguous — nothing else calls its app
    # instance that. Consulted only when the file imports no HTTP server.
    FASTIFY_RECEIVER_MARKER =
      /\bfastify\s*\.\s*(?:get|post|put|patch|delete|head|options|query|all|route|register)\s*\(/

    def self.other_shared_extractor_framework?(content : String, framework : Symbol) : Bool
      return false if content_matches?(content, OWN_EXTRACTOR_MARKER[framework])
      return true if content_matches?(content, OTHER_EXTRACTOR_MARKER[framework])
      if framework != :fastify && !content_matches?(content, HTTP_SERVER_LIBRARY_MARKER) &&
         content_matches?(content, FASTIFY_RECEIVER_MARKER)
        return true
      end
      # Client constructors only disqualify a file that stands up no server of
      # its own — a test that spins up an Express app and then calls it keeps
      # its routes.
      if content_matches?(content, HTTP_CLIENT_CONSTRUCTOR_MARKER) &&
         !content_matches?(content, HTTP_SERVER_LIBRARY_MARKER)
        return true
      end

      content_matches?(content, SIBLING_FRAMEWORK_MARKER)
    end

    # A Next.js pages-router tRPC mount: a `[trpc]` / `[...trpc]` file (the
    # adapter reads the procedure path from that query key) handing a router
    # to `createNextApiHandler`. Its URLs are the router's procedures, which
    # ts_trpc emits, not a `{trpc}` catch-all.
    TRPC_NEXT_MOUNT_BASENAME = /\A\[(?:\.\.\.)?trpc\]\.[cm]?[jt]sx?\z/

    def self.trpc_next_mount?(file_path : String, content : String) : Bool
      File.basename(file_path).matches?(TRPC_NEXT_MOUNT_BASENAME) && content.includes?("createNextApiHandler")
    end

    # The handler step (`handler_step`) resolved to a definition when it is a
    # plain reference (`login`, `users.create`, `auth()`), possibly in a
    # transparent wrapper (`asyncHandler(login)`); nil for an inline closure.
    # `unwrap_guards`: the caller's auth tagger reports a refusing wrapper
    # (`withAuth(list)`) as the guard, so the handler is what it wraps.
    def self.named_handler(step : String, content : String, file_path : String, unwrap_guards : Bool = false) : Handler?
      Noir::JSHandlerResolver.resolve(step, content, file_path, unwrap_guards)
    rescue
      # Best-effort field: a resolver error must not cost the route — the
      # per-file isolation above this would drop every route in the file.
      nil
    end

    # A function literal: `function`, `x =>`, or a parameter list then `=>`
    # (`async (ctx: Context<{ id: string }>) => …`). `(a || b)` is not one.
    INLINE_FUNCTION_RE = /\A\s*(?:async\s+)?(?:function\b|[A-Za-z_$][\w$]*\s*=>|\([^()]*(?:\([^()]*\)[^()]*)*\)\s*(?::[^=]*)?=>)/

    # The closure written inline as the handler step (`router.get('/x',
    # auth(), async (ctx) => {…})`, or inside a transparent wrapper:
    # `asyncHandler(async (req, res) => {…})`) has no name to resolve; it is
    # the handler, at the line it starts on.
    def self.inline_handler(step : String, line : Int32, content : String, file_path : String, unwrap_guards : Bool = false) : Handler?
      arg = step
      3.times do
        inner = Noir::JSHandlerResolver.unwrap(arg, content, file_path, unwrap_guards) || break
        line += arg[0, inner[1]].count('\n')
        arg = inner[0]
      end
      return if !arg.matches?(INLINE_FUNCTION_RE) || arg.matches?(ERROR_HANDLER_SIGNATURE_RE)
      Handler.new("closure", file_path, line)
    rescue
      nil
    end

    LOCALS_READ_RE  = /\b(?:res|response)\s*\.\s*locals\b/
    LOCALS_WRITE_RE = /\b(?:res|response)\s*\.\s*locals\s*(?:\.\s*[\w$]+|\[[^\]]+\])?\s*=(?!=)/

    # The route argument that serves the request, as {source, line it starts
    # on, index, whether it precedes the renderer}: the last one, unless the last one is a shared renderer
    # (`router.get('/', load, respond)`: `respond` sends whatever the step
    # before it left on `res.locals`, and ends many registrations). Then it
    # is the step before it, when that step is the route's own work: an
    # inline closure, or a definition that writes `res.locals`, that calls
    # `next()` and is not a guard. A pass-through like `noCache` is not.
    def self.handler_step(content : String, start_byte : Int32, file_path : String, offsets : ByteOffsets,
                          unwrap_guards : Bool = false, last_step_counts : Proc(Hash(String, Int32))? = nil) : Tuple(String, Int32, Int32, Bool)?
      return if start_byte < 0
      open_paren = content.byte_index('(', start_byte) || return
      close_paren = JSLiteralScanner.find_matching_paren_at_byte(content, open_paren) || return
      args_slice = content.byte_slice(open_paren + 1, close_paren - open_paren - 1)
      # A trailing comma (`asyncHandler(…),\n)`) leaves an empty last span.
      spans = Noir::TopLevelSplit.split_spans(args_slice, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, 0, args_slice.size).reject(&.[0].blank?)
      return if spans.empty?
      idx = spans.size - 1
      if idx >= 2 && last_step_counts && shared_renderer?(spans[idx][0].strip, content, file_path, last_step_counts) &&
         prepares_for_renderer?(spans[idx - 1][0], content, file_path, unwrap_guards)
        idx -= 1
      end
      arg, pos = spans[idx]
      leading = arg.size - arg.lstrip.size
      {arg.strip, offsets.line(open_paren) + args_slice[0, pos + leading].count('\n'), idx, idx < spans.size - 1}
    rescue
      nil
    end

    # A named step that responds with `res.locals` and is the last argument
    # of at least two route registrations in this file.
    private def self.shared_renderer?(step : String, content : String, file_path : String, last_step_counts : Proc(Hash(String, Int32))) : Bool
      return false unless step.matches?(/\A[A-Za-z_$][\w$.]*\z/)
      handler = Noir::JSHandlerResolver.resolve(step, content, file_path) || return false
      return false unless handler_definition_facts(handler, false).try(&.renders_locals)
      last_step_counts.call[step] >= 2
    end

    private def self.prepares_for_renderer?(step : String, content : String, file_path : String, unwrap_guards : Bool) : Bool
      body = step
      3.times do
        inner = Noir::JSHandlerResolver.unwrap(body, content, file_path, unwrap_guards) || break
        body = inner[0]
      end
      return body.matches?(BARE_NEXT_RE) && !guard_definition?(body) if body.matches?(INLINE_FUNCTION_RE)
      handler = Noir::JSHandlerResolver.resolve(step, content, file_path, unwrap_guards) || return false
      facts = handler_definition_facts(handler, false) || return false
      facts.passes_on && facts.writes_locals && !facts.guard
    end

    def self.route_arguments(content : String, start_byte : Int32) : Array(String)
      return [] of String if start_byte < 0
      open_paren = content.byte_index('(', start_byte) || return [] of String
      close_paren = JSLiteralScanner.find_matching_paren_at_byte(content, open_paren) || return [] of String
      args_slice = content.byte_slice(open_paren + 1, close_paren - open_paren - 1)
      Noir::TopLevelSplit.split_spans(args_slice, ',', Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, 0, args_slice.size).map(&.[0]).reject(&.blank?)
    end

    # Callees of the route-specific steps before the handler. In Express's
    # handler-chain style they do part of the route's work: juice-shop's
    # `app.post('/file-upload', …, checkFileType, handleZipFileUpload,
    # handleXmlUpload, handleYamlUpload)` extracts the zip and parses the
    # XML in steps the last argument never reaches. Only steps that resolve
    # to app source count (`uploadToMemory.single('file')` and
    # `express.json()` do not), a guard step reads as no callees
    # (`read_handler_facts`), and the caller adds these after the handler's
    # own. Steps nearest the handler come first, so under
    # `Callee::MAX_PER_ENDPOINT` they outrank the leading validators.
    def self.chain_step_callees(steps : Array(String), content : String, file_path : String) : Array(JSCalleeExtractor::Entry)
      steps.reverse.flat_map do |step|
        handler = Noir::JSHandlerResolver.resolve(step, content, file_path)
        facts = handler ? handler_definition_facts(handler, true) : nil
        facts ? facts.callees : [] of JSCalleeExtractor::Entry
      end
    rescue
      [] of JSCalleeExtractor::Entry
    end

    # What a resolved handler's definition reads and calls. `app.get('/x',
    # search())` in server.ts has nothing on its own line; the `req.query.q`
    # and the `sequelize.query(...)` live in routes/search.ts, and an agent
    # asking `--sink sql` needs them on the route. One hop: the definition's
    # own body (for a factory, that includes the closure it returns), cached
    # per definition because factories are reused across routes.
    # `responds` says the body answers the request itself (sends and never
    # calls bare `next()`), which is what tells a path-mounted handler from
    # a path-mounted guard.
    record HandlerFacts, params : Array(Param), callees : Array(JSCalleeExtractor::Entry), responds : Bool, guard : Bool = false,
      renders_locals : Bool = false, passes_on : Bool = false, writes_locals : Bool = false, sends : Bool = true

    RESPONDS_RE  = /\b(?:res|response|reply)\s*(?:\.status\s*\([^)]*\)\s*)?\.(?:send|sendStatus|sendFile|sendfile|json|jsonp|render|end|redirect|download|write)\s*\(/
    BARE_NEXT_RE = /\bnext\s*\(\s*\)/
    # A router factory (`module.exports = () => { router.get('/:id', …);
    # return router }`) sends inside the routes it registers; it is a
    # mount, not a handler.
    ROUTER_BODY_RE = /\bRouter\s*\(|\breturn\s+\w*[rR]outer\b|\.(?:get|post|put|delete|patch|all|route)\s*\(\s*['"`]\//

    # Mirrors ExpressAuthTagger::REFUSING_DEFINITION: a definition whose only
    # response is a 401/403 refusal (or that calls bare `next()` without
    # sending a non-refusal response) is a middleware/guard, not the route's
    # handler, so its body must not pollute the route's params or callees.
    GUARD_REFUSAL_RE           = /\bexpress[jJ]wt\s*\(|\bpassport\.authenticate\s*\(|(?:\b(?:res|response|reply)\s*\.\s*)?(?:status|sendStatus|send)\s*\(\s*40[13]\s*\)\s*(?:\.\s*(?:json|send|end)\s*\([^)]*\))?|\bnext\s*\(\s*(?:new\s+)?\w*(?:Unauthori[sz]ed|Forbidden)\w*|\bcreateError\s*\(\s*40[13]\b|\bnext\s*\(\s*\{[^}]*\b40[13]\b/
    ERROR_HANDLER_SIGNATURE_RE = /\A\s*(?:async\s+)?(?:function(?:\s+[A-Za-z_$][\w$]*)?\s*)?\(\s*err\w*\s*[,:]/
    INLINE_CLOSURE_START_RE    = /\A\s*(?:async\s+)?(?:function\b|\(|[A-Za-z_$][\w$]*\s*=>)/

    @@handler_facts = Hash(UInt64, HandlerFacts).new
    @@handler_facts_mutex = Mutex.new

    Noir::ExtractionResultCache.register_clearer do
      @@handler_facts_mutex.synchronize { @@handler_facts.clear }
      @@stripped_sources_mutex.synchronize { @@stripped_sources.clear }
    end

    # Comment-stripped definition files: many handlers live in, and hand
    # their request to, the same few modules.
    @@stripped_sources = Hash(String, String).new
    @@stripped_sources_mutex = Mutex.new

    private def self.stripped_source(path : String) : String
      if hit = @@stripped_sources_mutex.synchronize { @@stripped_sources[path]? }
        return hit
      end
      text = strip_js_comments(TextFile.read(path))
      @@stripped_sources_mutex.synchronize { ExtractionResultCache.store_capped(@@stripped_sources, path, text, 512) }
    end

    # Whether the `(req, res, next)` definition at `line` does anything with
    # its response besides `res.locals`: sends, sets, or hands it to a
    # function that answers (`helpers.formatApiResponse(200, res)`). A shape
    # without a response parameter (Koa's `(ctx, next)`) is taken to.
    private def self.touches_response?(body : String, content : String, line : Int32) : Bool
      params = definition_params(content, line)
      response = params[1]? if params && params.size >= 3
      return true if response.nil? || response.empty?
      return true if body.matches?(/(?<![\w$.])#{Regex.escape(response)}\b(?!\s*\.\s*locals\b)/)
      # `req.res.json(item)`, or `reply(req, item)` answering through the request.
      request = params.try(&.first?) || ""
      return false if request.empty?
      req = Regex.escape(request)
      body.matches?(/(?<![\w$.])#{req}\s*\.\s*res\b|(?<![\w$.])(?!next\b)[A-Za-z_$][\w$.]*\s*\((?:[^()]*,)?\s*#{req}\s*[,)]/)
    end

    # Whether a resolved step serves the request: not a guard, and not a
    # pass-through that only calls `next()` (`router.all('/api/*',
    # prepareAPI)` registers no handler). Unknown facts keep the step.
    # The step before a shared renderer (`handler_step`) passes on by design.
    def self.serves?(facts : HandlerFacts?, before_renderer : Bool = false) : Bool
      return true unless facts
      return false if facts.guard
      before_renderer || !(facts.passes_on && !facts.sends)
    end

    def self.handler_definition_facts(handler : Handler, include_callees : Bool) : HandlerFacts?
      path = handler.path || return
      line = handler.line || return
      key = ExtractionResultCache.key(path, "js_handler_facts", line.to_s, include_callees ? "callees" : "")
      ExtractionResultCache.fetch(@@handler_facts, key, @@handler_facts_mutex) do
        read_handler_facts(path, line, include_callees)
      end
    rescue
      # Same contract as `named_handler`: never cost the route.
      nil
    end

    # Facts for an inline closure passed directly to `app.use('/path', (req, res) => { … })`.
    # Returns nil when `source` is not a function expression or arrow closure.
    def self.inline_closure_facts(source : String, path : String, line : Int32, include_callees : Bool) : HandlerFacts?
      stripped = source.strip
      return unless stripped.matches?(INLINE_CLOSURE_START_RE)
      return if stripped.matches?(ERROR_HANDLER_SIGNATURE_RE)

      body_open = if stripped.matches?(/\A(?:async\s+)?function\b/)
                    paren_open = stripped.byte_index('(') || return
                    paren_close = JSLiteralScanner.find_matching_paren_at_byte(stripped, paren_open) || return
                    stripped.byte_index('{', paren_close) || return
                  elsif (paren_open = stripped.byte_index('(')) && stripped.byte_slice(0, paren_open).matches?(/\A(?:async\s*)?\z/)
                    paren_close = JSLiteralScanner.find_matching_paren_at_byte(stripped, paren_open) || return
                    rest = stripped.byte_slice(paren_close + 1, stripped.bytesize - paren_close - 1)
                    arrow_match = rest.match(/\A(?:\s*:\s*[^{=;]+)?\s*=>\s*/m) || return
                    after_arrow = paren_close + 1 + arrow_match.byte_end(0)
                    after_arrow < stripped.bytesize && stripped.to_slice[after_arrow] == '{'.ord ? after_arrow : nil
                  elsif arrow_match = stripped.match(/\A(?:async\s+)?[A-Za-z_$][\w$]*\s*=>\s*/)
                    after_arrow = arrow_match.byte_end(0)
                    after_arrow < stripped.bytesize && stripped.to_slice[after_arrow] == '{'.ord ? after_arrow : nil
                  else
                    return
                  end

      body = if body_open && (body_close = JSLiteralScanner.find_matching_brace_at_byte(stripped, body_open))
               stripped.byte_slice(body_open + 1, body_close - body_open - 1)
             else
               stripped
             end

      responds = body.matches?(RESPONDS_RE) && !body.matches?(BARE_NEXT_RE) && !body.matches?(ROUTER_BODY_RE) && !guard_definition?(body)
      return empty_handler_facts unless responds

      context = Endpoint.new("", "")
      extract_body_params(stripped, context)
      extract_query_params(stripped, context)
      extract_header_params(stripped, context)
      extract_cookie_params(stripped, context)
      extract_path_params(stripped, context)

      callees = if include_callees
                  language = path.matches?(/\.[mc]?tsx?\z/) ? :typescript : :javascript
                  JSCalleeExtractor.callees_for_function_body(body, path, line, language: language)
                else
                  [] of JSCalleeExtractor::Entry
                end
      HandlerFacts.new(context.params, callees, true)
    rescue
      nil
    end

    def self.apply_handler_facts(endpoint : Endpoint, facts : HandlerFacts?)
      return unless facts
      facts.params.each do |param|
        # A handler shared by several routes reads every route's params
        # (`renderShare` reads `ctx.params.documentSlug` for `/s/:shareId`
        # too); a path param this route's template does not bind is never set.
        next if param.param_type == "path" && !route_binds_path_param?(endpoint.url, param.name)
        endpoint.push_param(param)
      end
      push_callees(endpoint, facts.callees)
    end

    # `:name`, `{name}`, `{*name}`, `*name`; a regex route (`(`) may bind
    # anything, so it keeps every param.
    private def self.route_binds_path_param?(url : String, name : String) : Bool
      return true if url.includes?('(')
      url.includes?(":#{name}") || url.includes?("{#{name}") || url.includes?("*#{name}")
    end

    def self.push_callees(endpoint : Endpoint, callees : Array(JSCalleeExtractor::Entry)?)
      callees.try &.each do |name, callee_path, callee_line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
      end
    end

    private def self.guard_definition?(body : String) : Bool
      body.matches?(GUARD_REFUSAL_RE) && !body.gsub(GUARD_REFUSAL_RE, "").matches?(RESPONDS_RE)
    end

    private def self.read_handler_facts(path : String, line : Int32, include_callees : Bool) : HandlerFacts
      content = stripped_source(path)
      line_start = 0
      (line - 1).times do
        line_start = (content.byte_index('\n', line_start) || return empty_handler_facts) + 1
      end
      line_end = content.byte_index('\n', line_start) || content.bytesize
      # The body brace is the one after the last `=>` on the line (or after
      # a `function` signature's closing `)`), so destructured parameters
      # `({ query })` and `Request<{ id: string }>` annotations are not
      # mistaken for the function body.
      # ponytail: a brace on a later line (a signature that wraps) and a
      # concise arrow (`= () => expressJwt(...)`) yield the definition line only.
      brace_from = line_start
      while (arrow = content.byte_index("=>", brace_from)) && arrow < line_end
        brace_from = arrow + 2
      end
      if brace_from == line_start && (paren_open = content.byte_index('(', line_start)) && paren_open < line_end
        if paren_close = JSLiteralScanner.find_matching_paren_at_byte(content, paren_open)
          brace_from = paren_close + 1 if paren_close < line_end
        end
      end
      open = content.byte_index('{', brace_from)
      # A brace opens the function body only if it immediately follows `=>`
      # or a parameter list `)`. A brace after `(` is an object argument in
      # a concise arrow (`() => expressJwt({ ... })`), so the body is the
      # definition line itself.
      is_body_brace = false
      if open && open < line_end
        prev = open - 1
        bytes = content.to_slice
        while prev >= line_start && bytes[prev].unsafe_chr.ascii_whitespace?
          prev -= 1
        end
        is_body_brace = prev >= line_start && (bytes[prev] == '>'.ord || bytes[prev] == ')'.ord)
      end

      if is_body_brace && open && open < line_end && (close = JSLiteralScanner.find_matching_brace_at_byte(content, open))
        body = content.byte_slice(open + 1, close - open - 1)
        signature_and_body = content.byte_slice(line_start, close - line_start + 1)
      else
        body = content.byte_slice(line_start, line_end - line_start)
        signature_and_body = body
      end

      context = Endpoint.new("", "")
      extract_body_params(signature_and_body, context)
      extract_query_params(signature_and_body, context)
      extract_header_params(signature_and_body, context)
      extract_cookie_params(signature_and_body, context)
      extract_path_params(signature_and_body, context)

      guard = guard_definition?(body)
      request_callee_reads(body, content, path, line, context) unless guard
      callees = if include_callees && !guard
                  language = path.matches?(/\.[mc]?tsx?\z/) ? :typescript : :javascript
                  JSCalleeExtractor.callees_for_function_body(body, path, line, language: language)
                else
                  [] of JSCalleeExtractor::Entry
                end
      responds = body.matches?(RESPONDS_RE) && !body.matches?(BARE_NEXT_RE) && !body.matches?(ROUTER_BODY_RE) && !guard
      renders_locals = body.matches?(RESPONDS_RE) && body.matches?(LOCALS_READ_RE)
      HandlerFacts.new(context.params, callees, responds, guard, renders_locals, body.matches?(BARE_NEXT_RE), body.matches?(LOCALS_WRITE_RE),
        touches_response?(body, content, line))
    end

    REQUEST_CALL_RE       = /(?<![\w$.])((?:[A-Za-z_$][\w$]*\s*\.\s*)*[A-Za-z_$][\w$]*)\s*\(/
    NOT_A_CALLEE_RE       = /\A(?:if|for|while|switch|catch|function|async|return|typeof|await|new|next|super)\z|\A(?:res|response)\./
    MAX_REQUEST_CALLEES   = 12
    REQUEST_RECEIVER_NAME = /\A(?:req|request)\z/

    # What the functions a handler hands its request to read off it: `const
    # { uid } = await getUidFromToken(req, res)` reads `req.query.uid` in
    # `getUidFromToken`. One hop, definitions in the scan only, and only a
    # call that passes the request object itself (`fire('x', { req })` hands
    # over a record, `get(req.params.id)` a value).
    private def self.request_callee_reads(body : String, content : String, path : String, line : Int32, context : Endpoint)
      followed = 0
      # A dispatcher calls the same helper from many branches
      # (`errorForbidden(req, res)`); each is read once.
      seen = Set(String).new
      body.scan(REQUEST_CALL_RE) do |m|
        break if followed >= MAX_REQUEST_CALLEES
        callee = m[1].gsub(/\s+/, "")
        next if callee.matches?(NOT_A_CALLEE_RE)
        next if seen.includes?(callee)
        open = m.end(0) - 1
        close = JSLiteralScanner.find_matching_paren(body, open) || next
        args = TopLevelSplit.split(body[open + 1...close], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map(&.strip)
        position = args.index(&.matches?(REQUEST_RECEIVER_NAME)) || next
        seen << callee
        target = Noir::JSHandlerResolver.resolve(callee, content, path) || next
        target_path = target.path || next
        target_line = target.line || next
        next if target_path == path && target_line == line
        followed += 1
        text = target_path == path ? content : stripped_source(target_path)
        name = definition_params(text, target_line).try(&.[position]?) || next
        # `fromRemote({ session }, client)`: no name to read through.
        next if name.empty?
        reads = definition_body(text, target_line)
        reads = reads.gsub(/(?<![\w$.])#{Regex.escape(name)}(?=\s*\??\.)/, "req") unless name.matches?(REQUEST_RECEIVER_NAME)
        extract_body_params(reads, context)
        extract_query_params(reads, context)
        extract_header_params(reads, context)
        extract_cookie_params(reads, context)
      end
    rescue
      nil
    end

    # The parameter names of the function defined at `line` (`function f(req,
    # res)`, `f = async (req, res) =>`, `f = req =>`); "" for a destructured
    # or rest parameter.
    def self.definition_params(content : String, line : Int32) : Array(String)?
      line_start = 0
      (line - 1).times do
        line_start = (content.byte_index('\n', line_start) || return) + 1
      end
      line_end = content.byte_index('\n', line_start) || content.bytesize
      own_line = content.byte_slice(line_start, line_end - line_start)
      if fn = own_line.match(/\bfunction\b\s*\*?\s*[\w$]*\s*\(/)
        open = fn.end(0) - 1
        close = JSLiteralScanner.find_matching_paren(own_line, open) || return
      elsif arrow = own_line.rindex("=>")
        head = own_line[0...arrow].rstrip
        unless head.ends_with?(')')
          return head.match(/([A-Za-z_$][\w$]*)\z/).try { |mm| [mm[1]] }
        end
        close = head.size - 1
        depth = 0
        open = nil
        close.downto(0) do |idx|
          case head[idx]
          when ')' then depth += 1
          when '('
            depth -= 1
            if depth == 0
              open = idx
              break
            end
          end
        end
        open || return
      else
        return
      end
      TopLevelSplit.split(own_line[open + 1...close], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map do |param|
        param.strip.match(/\A([A-Za-z_$][\w$]*)/).try(&.[1]) || ""
      end
    end

    # The body of the function defined at `line` of `content`, its signature
    # allowed to wrap lines (`function v(\n  ctx,\n): Promise<{ a: A }> {`):
    # the first `{` after the last `=>` on the line, or after the parameter
    # list, that follows `)` or `>` — braces inside a return type follow `<`
    # or `:`. A concise body (`= () => jwt({ … })`) yields the definition line.
    def self.definition_body(content : String, line : Int32) : String
      line_start = 0
      (line - 1).times do
        line_start = (content.byte_index('\n', line_start) || return "") + 1
      end
      line_end = content.byte_index('\n', line_start) || content.bytesize
      own_line = content.byte_slice(line_start, line_end - line_start)
      from = line_start
      while (arrow = content.byte_index("=>", from)) && arrow < line_end
        from = arrow + 2
      end
      if from == line_start
        paren_open = content.byte_index('(', line_start) || return own_line
        return own_line if paren_open >= line_end
        from = (JSLiteralScanner.find_matching_paren_at_byte(content, paren_open) || return own_line) + 1
      end
      bytes = content.to_slice
      stop = Math.min(content.bytesize, from + 400)
      pos = from
      type_depth = 0 # braces of a return type (`Promise<{ a: A; b: B }>`)
      while pos < stop
        case bytes[pos]
        when ';'.ord
          break if type_depth == 0
        when '}'.ord
          type_depth -= 1
          break if type_depth < 0
        when '{'.ord
          prev = pos - 1
          while prev >= from && bytes[prev].unsafe_chr.ascii_whitespace?
            prev -= 1
          end
          if type_depth == 0 && prev >= from - 1 && (bytes[prev] == ')'.ord || bytes[prev] == '>'.ord)
            close = JSLiteralScanner.find_matching_brace_at_byte(content, pos) || break
            return content.byte_slice(pos + 1, close - pos - 1)
          end
          type_depth += 1
        end
        pos += 1
      end
      own_line
    end

    private def self.empty_handler_facts : HandlerFacts
      HandlerFacts.new([] of Param, [] of JSCalleeExtractor::Entry, false, false)
    end

    def self.attach_callees(endpoint : Endpoint,
                            callees_by_route : Hash(String, Array(JSCalleeExtractor::Entry)),
                            method : String,
                            path : String,
                            line : Int32)
      push_callees(endpoint, callees_by_route[JSCalleeExtractor.route_key(method, path, line)]?)
    end

    # Normalize HTTP method names to standard format
    def self.normalize_http_method(method : String) : String
      method = method.upcase

      # Standardize HTTP methods
      case method
      when "DEL"
        return "DELETE"
      when "ALL"
        return "ALL" # Keep ALL as-is for special handling
      when "OPTIONS"
        return "OPTIONS"
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "QUERY"
        return method
      end

      # Return the original (uppercased) method if no specific normalization needed
      method
    end

    # Memoizes the direct-call patterns built in extract_params_from_context;
    # the alternation is derived from the route's HTTP method, so the key set
    # is tiny. The plain Hash is safe under the analyzers' parallel file
    # scans, which run on the default execution context (parallelism 1:
    # one fiber at a time, whatever OS thread it is on). Not safe to call
    # from `Noir::WorkerThreads`, whose fibers run in parallel.
    @@direct_call_res = Hash(String, Regex).new
    HANDLER_ANCHOR_RE = /\bfunction\b|=>/

    # Ceiling on the prefixes one router collects. The (router, prefix)
    # dedupe already bounds the work; this only stops a diamond lattice of
    # parallel edges from multiplying without end. A shared router mounted
    # under many paths stays well below it. Shared with JSParser's
    # same-file router resolution.
    MAX_MOUNT_PREFIXES = JSParser::MAX_MOUNT_PREFIXES

    EXPORT_DECL_RE         = /\bexport\s+(?:const|let|var)\s+([A-Za-z_$][\w$]*)/
    EXPORT_LIST_RE         = /\bexport\s*\{([^}]*)\}(?!\s*from\b)/
    CJS_EXPORT_OBJECT_RE   = /(?:\bmodule\.exports\s*=|\bexport\s+default)\s*\{([^}]*)\}/
    CJS_EXPORT_PROPERTY_RE = /\b(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)\s*[;\n]/
    EXPORT_ALIAS_RE        = /\A([A-Za-z_$][\w$]*)\s+as\s+([A-Za-z_$][\w$]*)\z/
    EXPORT_KEY_VALUE_RE    = /\A([A-Za-z_$][\w$]*)\s*:\s*([A-Za-z_$][\w$]*)\z/
    EXPORT_IDENT_RE        = /\A[A-Za-z_$][\w$]*\z/
    ROUTE_RECEIVER_RE      = /\A([A-Za-z_$][\w$]*)\s*\./

    private def self.identifier_byte?(byte : UInt8) : Bool
      byte.unsafe_chr.ascii_alphanumeric? || byte === '_' || byte === '$'
    end

    # Local binding => the names it is exported under. An importer that
    # takes a router by name (`const { usersRouter } = require('./users')`,
    # `import { usersRouter } from './users'`, `users.router`) records the
    # mount prefix under that *exported* name, and the routes are registered
    # on the *local* binding, so the two have to be joined here. Covers
    # `export const x = …`, `export { a as b }`, `module.exports = { a, b: c }`,
    # `export default { a, b: c }`
    # and `(module.)exports.b = a`.
    def self.export_bindings(content : String) : Hash(String, Array(String))
      bindings = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }
      content.scan(EXPORT_DECL_RE) { |m| bindings[m[1]] << m[1] }
      content.scan(CJS_EXPORT_PROPERTY_RE) { |m| bindings[m[2]] << m[1] }
      content.scan(EXPORT_LIST_RE) do |m|
        m[1].split(',').each do |item|
          item = item.strip
          if alias_match = item.match(EXPORT_ALIAS_RE)
            bindings[alias_match[1]] << alias_match[2]
          elsif item.matches?(EXPORT_IDENT_RE)
            bindings[item] << item
          end
        end
      end
      content.scan(CJS_EXPORT_OBJECT_RE) do |m|
        m[1].split(',').each do |item|
          item = item.strip
          if pair = item.match(EXPORT_KEY_VALUE_RE)
            bindings[pair[2]] << pair[1]
          elsif item.matches?(EXPORT_IDENT_RE)
            bindings[item] << item
          end
        end
      end
      bindings
    end

    # `const NAME = 'lit'`, and `process.env.X || 'lit'` (`??` too): the
    # literal is what the app serves when the variable is unset.
    # The literal must end the expression: `'/api/' + version` is no constant.
    STRING_CONST_RE = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::\s*[\w.]+\s*)?=\s*(?:process\.env(?:\.\w+|\[['"][^'"]+['"]\])\s*(?:\|\||\?\?)\s*)?(?:'([^'\n]*)'|"([^"\n]*)"|`([^`$]*)`)(?:\s+as\s+const)?(?=\s*(?:[;,\n]|\z))/
    # `import { A, B as C } from './x'`, `const { A, B: C } = require('./x')`.
    NAMED_RELATIVE_IMPORT_RE = /\bimport\s*(?:[\w$]+\s*,\s*)?\{([^}]*)\}\s*from\s*['"](\.[^'"]*)['"]|\b(?:const|let|var)\s*\{([^}]*)\}\s*=\s*require\s*\(\s*['"](\.[^'"]*)['"]\s*\)/

    def self.string_constants(content : String) : Hash(String, String)
      constants = Hash(String, String).new
      content.scan(STRING_CONST_RE) { |m| constants[m[1]] = m[2]? || m[3]? || m[4] }
      constants
    end

    # The file's own string constants plus those it imports by name from a
    # relative module (`import { BASE_URL } from './config'`); local wins.
    def self.file_string_constants(file_path : String, content : String) : Hash(String, String)
      constants = Hash(String, String).new
      if content.includes?('{') && (content.includes?("from") || content.includes?("require"))
        content.scan(NAMED_RELATIVE_IMPORT_RE) do |m|
          names = m[1]? || m[3]
          target = Noir::ImportGraph.resolve_relative_import(file_path, m[2]? || m[4]) || next
          exported = string_constants(stripped_source(target))
          names.split(',').each do |item|
            parts = item.strip.split(/\s*:\s*|\s+as\s+/)
            value = exported[parts.first]? || next
            constants[parts.last] = value
          end
        rescue File::Error | IO::Error
        end
      end
      constants.merge!(string_constants(content))
    end

    # Substitutes every `${NAME}` that `constants` knows; the rest stay.
    def self.resolve_template(template : String, constants : Hash(String, String)) : String
      return template unless template.includes?("${")
      template.gsub(/\$\{\s*([A-Za-z_$][\w$]*)\s*\}/) { |whole, m| constants[m[1]]? || whole }
    end

    # A template-literal mount path (`` `/${rootPath}` ``) as a rooted path.
    def self.resolve_mount_template(template : String, file_path : String, content : String) : String
      return template unless template.includes?("${")
      "/#{resolve_template(template, file_string_constants(file_path, content))}".squeeze('/')
    end

    # Pushes mount prefixes along `{parent, prefix, child}` edges into
    # `prefixes`, starting from each parent's existing prefixes (or
    # `fallback` when it has none, without recording that on the parent).
    #
    # Depth-first with the routers on the current mount path excluded, so a
    # self-mount (`router.use('/v1', router.routes())`), a plugin that
    # registers itself, or an a -> b -> a cycle is expanded at most once
    # instead of growing the prefix list without bound — the fixpoint loops
    # this replaced appended to the array they were iterating.
    #
    # Returns true when some router hit MAX_MOUNT_PREFIXES and lost prefixes.
    def self.propagate_mount_prefixes(edges : Array(Tuple(String, String, String)),
                                      prefixes : Hash(String, Array(String)),
                                      fallback : Array(String) = [] of String) : Bool
      by_parent = edges.group_by(&.[0])
      starts = by_parent.keys.map do |parent|
        own = prefixes[parent]?
        {parent, own.nil? || own.empty? ? fallback : own.dup}
      end
      on_path = Set(String).new
      capped = false
      starts.each do |parent, parent_prefixes|
        on_path << parent
        parent_prefixes.each do |prefix|
          capped = true if descend_mounts(parent, prefix, by_parent, prefixes, on_path)
        end
        on_path.delete(parent)
      end
      capped
    end

    # Returns true when a router's prefix list was full.
    private def self.descend_mounts(node : String, prefix : String,
                                    by_parent : Hash(String, Array(Tuple(String, String, String))),
                                    prefixes : Hash(String, Array(String)), on_path : Set(String)) : Bool
      capped = false
      by_parent[node]?.try &.each do |_, edge_prefix, child|
        next if on_path.includes?(child)
        combined = URLPath.join(prefix, edge_prefix)
        list = prefixes[child]? || (prefixes[child] = [] of String)
        next if list.includes?(combined)
        if list.size >= MAX_MOUNT_PREFIXES
          capped = true
          next
        end
        list << combined
        on_path << child
        capped = true if descend_mounts(child, combined, by_parent, prefixes, on_path)
        on_path.delete(child)
      end
      capped
    end

    # Equivalent to matching /['"`]<literal>['"`]/ — the literal bracketed by
    # a quote character on each side — without compiling a per-path regex.
    private def self.quoted_substring?(window : String, literal : String) : Bool
      search_from = 0
      while found = window.index(literal, search_from)
        after_idx = found + literal.size
        if found > 0 && after_idx < window.size
          before = window[found - 1]
          after = window[after_idx]
          if (before == '\'' || before == '"' || before == '`') &&
             (after == '\'' || after == '"' || after == '`')
            return true
          end
        end
        search_from = found + 1
      end
      false
    end

    # Bytes after a route's start searched for its declaration when the
    # direct `.verb(` probe misses. The declaration is the call at the
    # route's own position; searching the whole file found the first route
    # elsewhere with the same path (wrong handler) and cost O(file) per route.
    DECLARATION_SEARCH_BYTES = 2000

    # Every offset here is a BYTE offset into `offsets.content` (see
    # ByteOffsets) so a route's cost is local to its own text.
    def self.extract_params_from_context(offsets : ByteOffsets, pattern : JSRoutePattern, endpoint : Endpoint, file_path : String? = nil)
      content = offsets.content
      # Extract additional parameters from the route handler content
      # Look for the route declaration and then analyze the handler function
      method_name = pattern.method.downcase

      # Create possible method names for both dot notation and bracket notation
      method_variations = [method_name]

      # Handle the case where 'del' might be used instead of 'delete' in the code or vice versa
      if method_name == "delete"
        method_variations << "del"
      elsif method_name == "del"
        method_variations << "delete"
      elsif method_name == "options"
        method_variations << "opts" # Restify
      end

      # Generate all possible route declarations with different syntax patterns
      route_declarations = [] of String
      lookup_path = pattern.raw_path
      method_variations.each do |method|
        # Standard method call with single quotes
        route_declarations << "#{method}('#{lookup_path}'"
        # Method call with double quotes
        route_declarations << "#{method}(\"#{lookup_path}\""
        # Method call with template literals
        route_declarations << "#{method}(`#{lookup_path}`"
        # Bracket method notation: router['get']('/path', ...)
        route_declarations << "['#{method}']('#{lookup_path}'"
        route_declarations << "[\"#{method}\"](\"#{lookup_path}\""
        route_declarations << "['#{method}'](\"#{lookup_path}\""
        route_declarations << "[\"#{method}\"]('#{lookup_path}'"
      end

      # Also handle app.route('/path').method() pattern
      # In this case, search for route('/path')...method(
      route_declarations << "route('#{lookup_path}'"
      route_declarations << "route(\"#{lookup_path}\""
      route_declarations << "route(`#{lookup_path}`"

      # Find the index of any matching route declaration
      idx = nil
      found_declaration = ""
      start_byte = pattern.start_pos >= 0 ? offsets.byte(pattern.start_pos) : nil
      if start_byte && chain_link_at?(content, start_byte, method_variations)
        # A `route('/x').verb(...)` chain link starts at its own verb (see
        # JSRoutePattern#start_pos), and its arguments carry no path.
        idx = start_byte
        found_declaration = "direct"
      elsif start_byte
        search_window = offsets.window(start_byte, 500)
        method_alternation = method_variations.map { |method| Regex.escape(method) }.join("|")
        # Memoized — method_alternation has ~8 distinct values, and an
        # interpolated regex literal would recompile (full PCRE2 compile)
        # once per endpoint.
        direct_call_pattern = @@direct_call_res.fetch(method_alternation) do
          @@direct_call_res[method_alternation] = /(?:\.\s*(?:#{method_alternation})|\[\s*['"](?:#{method_alternation})['"]\s*\])\s*\(/i
        end
        if direct_match = search_window.match(direct_call_pattern)
          candidate_idx = start_byte + direct_match.byte_begin(0)
          open_paren = content.byte_index('(', candidate_idx)
          if open_paren
            arg_window = offsets.window(open_paren, 300)
            if quoted_substring?(arg_window, lookup_path)
              idx = candidate_idx
              found_declaration = "direct"
            end
          end
        end
      end

      # The declaration fallbacks search from the route's own position
      # (the whole file only when the parser gave none).
      scope_start = start_byte || 0
      scope = start_byte ? offsets.window(start_byte, DECLARATION_SEARCH_BYTES) : content

      route_declarations.each do |declaration|
        break if idx

        found_idx = scope.byte_index(declaration)
        if found_idx
          idx = scope_start + found_idx
          found_declaration = declaration
          break
        end
      end

      # Koa/@koa-router named routes put a route name before the real path:
      #   router.get("route-name", "/path", handler)
      if idx.nil?
        escaped_path = Regex.escape(lookup_path)
        method_variations.each do |method|
          named_route_pattern = /#{Regex.escape(method)}\s*\(\s*['"][^'"]+['"]\s*,\s*['"]#{escaped_path}['"]/
          if named_match = scope.match(named_route_pattern)
            idx = scope_start + named_match.byte_begin(0)
            found_declaration = method
            break
          end
        end
      end

      return unless idx

      # If we found a route() declaration, we need to find the specific .method() call after it
      if found_declaration.starts_with?("route(")
        # Look for the .method( pattern after the route declaration
        chain_window = offsets.window(idx, 216)
        method_variations.each do |method|
          method_idx = chain_window.byte_index(".#{method}(")
          if method_idx && method_idx > 0 && method_idx < 200
            idx += method_idx
            break
          end
        end
      end

      # Find the bounds of the method call arguments to keep the search scoped
      open_paren_idx = content.byte_index('(', idx)
      return unless open_paren_idx
      close_paren_idx = JSLiteralScanner.find_matching_paren_at_byte(content, open_paren_idx)
      return unless close_paren_idx

      args_start = open_paren_idx + 1
      return if close_paren_idx <= args_start

      args_slice = content.byte_slice(args_start, close_paren_idx - args_start)
      args_bytes = args_slice.to_slice

      # The handler is the last function argument. Walk the arguments'
      # functions in order, skipping each one's body: `rindex` over the
      # whole slice picked an arrow *inside* the handler
      # (`items.map(i => …)`) and scoped the param scan to that.
      handler = nil.as(Tuple(Int32, Int32)?) # {start, end} in args_slice
      search = 0
      while anchor = HANDLER_ANCHOR_RE.match_at_byte_index(args_slice, search)
        anchor_idx = anchor.byte_begin(0)
        arrow = anchor[0] == "=>"
        sig_start = arrow ? argument_start_before(args_bytes, search, anchor_idx) : anchor_idx
        body_open = if arrow
                      ws_end = anchor.byte_end(0)
                      while ws_end < args_bytes.size && args_bytes[ws_end].unsafe_chr.ascii_whitespace?
                        ws_end += 1
                      end
                      ws_end if ws_end < args_bytes.size && args_bytes[ws_end] == '{'.ord
                    elsif (params_open = args_slice.byte_index('(', anchor_idx)) &&
                          (params_close = JSLiteralScanner.find_matching_paren_at_byte(args_slice, params_open))
                      args_slice.byte_index('{', params_close)
                    end
        body_close = body_open && JSLiteralScanner.find_matching_brace_at_byte(args_slice, body_open)
        if body_open && body_close
          handler = {sig_start, body_close + 1}
          search = body_close + 1
        elsif arrow
          # Concise arrow (`(req, res) => res.json(req.query)`): the body is
          # the expression up to the end of this argument, skipped whole so
          # an arrow nested in it is not taken for the handler.
          expr_end = argument_end(args_bytes, anchor.byte_end(0))
          handler = {sig_start, expr_end}
          search = expr_end
        else
          handler = nil
          search = anchor.byte_end(0)
        end
      end

      extract_multer_params(handler ? args_slice.byte_slice(0, handler[0]) : args_slice, endpoint)

      return unless handler

      handler_body = args_slice.byte_slice(handler[0], handler[1] - handler[0])

      # Now analyze the handler body for req.body, req.query, etc.
      extract_body_params(handler_body, endpoint)
      extract_query_params(handler_body, endpoint)
      extract_header_params(handler_body, endpoint)
      extract_cookie_params(handler_body, endpoint)
      extract_path_params(handler_body, endpoint)
      # An inline closure hands its request to helpers as a named one does
      # (`setReturnToFromReferer(req)` reads the referer header).
      request_callee_reads(handler_body, content, file_path, -1, endpoint) if file_path
    end

    # True when `start` is a chained `.verb(` call's verb: one of `methods`
    # preceded by a `.` and followed by `(`.
    private def self.chain_link_at?(content : String, start : Int32, methods : Array(String)) : Bool
      bytes = content.to_slice
      prev = start - 1
      while prev >= 0 && bytes[prev].unsafe_chr.ascii_whitespace?
        prev -= 1
      end
      return false unless prev >= 0 && bytes[prev] == '.'.ord

      methods.any? do |method|
        stop = start + method.bytesize
        next false unless stop <= bytes.size && content.byte_slice(start, method.bytesize).compare(method, case_insensitive: true) == 0
        while stop < bytes.size && bytes[stop].unsafe_chr.ascii_whitespace?
          stop += 1
        end
        stop < bytes.size && bytes[stop] == '('.ord
      end
    end

    # Start of the argument containing `target`, scanning forward from `from`
    # and advancing past each top-level `,`.
    private def self.argument_start_before(bytes : Bytes, from : Int32, target : Int32) : Int32
      depth = 0
      quote = 0_u8
      start = from
      i = from
      while i < target
        byte = bytes[i]
        if quote != 0
          if byte == '\\'.ord
            i += 1
          elsif byte == quote
            quote = 0_u8
          end
        else
          case byte
          when '\''.ord, '"'.ord, '`'.ord
            quote = byte
          when '('.ord, '['.ord, '{'.ord
            depth += 1
          when ')'.ord, ']'.ord, '}'.ord
            depth -= 1 if depth > 0
          when ','.ord
            start = i + 1 if depth == 0
          end
        end
        i += 1
      end
      start
    end

    # End (exclusive) of the argument starting at byte `from` of an
    # argument list: its first top-level `,`, or the end of the list.
    private def self.argument_end(bytes : Bytes, from : Int32) : Int32
      depth = 0
      quote = 0_u8
      i = from
      while i < bytes.size
        byte = bytes[i]
        if quote != 0
          if byte == '\\'.ord
            i += 1
          elsif byte == quote
            quote = 0_u8
          end
        else
          case byte
          when '\''.ord, '"'.ord, '`'.ord
            quote = byte
          when '('.ord, '['.ord, '{'.ord
            depth += 1
          when ')'.ord, ']'.ord, '}'.ord
            depth -= 1 if depth > 0
          when ','.ord
            return i if depth == 0
          end
        end
        i += 1
      end
      bytes.size
    end

    # Delegate to JSLiteralScanner for literal-aware brace matching
    def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      JSLiteralScanner.find_matching_brace(content, open_brace_idx)
    end

    # Delegate to JSLiteralScanner for literal-aware paren matching
    def self.find_matching_paren(content : String, open_paren_idx : Int32) : Int32?
      JSLiteralScanner.find_matching_paren(content, open_paren_idx)
    end

    FINALE_RESOURCE_RE      = /\b(?:finale|epilogue)\s*\.\s*resource\s*\(/
    FINALE_ENDPOINTS_RE     = /\bendpoints\s*:\s*\[([^\]]*)\]/
    FINALE_FOR_OF_RE        = /\bfor\s*\(\s*(?:const|let|var)\s*\{([^}]*)\}\s*of\s+([A-Za-z_$][\w$]*)\s*\)\s*\{/
    FINALE_PLURAL_METHODS   = %w[GET POST]
    FINALE_SINGULAR_METHODS = %w[GET PUT DELETE]

    # finale-rest (and its predecessor epilogue) `finale.resource({ endpoints:
    # ['/users', '/users/:id'] })` registers list + create on the first path
    # and read + update + delete on the second (the first again when there
    # is no second). A `${name}` placeholder is expanded when an enclosing
    # `for (const { name } of models)` walks an array literal declared in the
    # same file (juice-shop's `autoModels`); any other placeholder drops the
    # path. Returns `{method, url, call offset}`; pass comment-stripped source.
    def self.finale_resource_routes(content : String) : Array(Tuple(String, String, Int32))
      routes = [] of Tuple(String, String, Int32)
      return routes unless content.includes?(".resource")
      content.scan(FINALE_RESOURCE_RE) do |m|
        call_start = m.begin(0)
        paren_close = find_matching_paren(content, m.end(0) - 1) || next
        list = content[call_start..paren_close].match(FINALE_ENDPOINTS_RE) || next
        paths = list[1].scan(/(['"`])(.*?)\1/).map(&.[2])
        next if paths.empty?
        {paths[0], paths[1]? || paths[0]}.each_with_index do |template, idx|
          methods = idx == 0 ? FINALE_PLURAL_METHODS : FINALE_SINGULAR_METHODS
          finale_expand(content, call_start, template).each do |url|
            methods.each { |method| routes << {method, url, call_start} }
          end
        end
      end
      routes.uniq
    end

    # ponytail: one placeholder, bound by a destructuring for-of over a
    # same-file array literal, values read as `key: 'literal'`; a general
    # constant evaluator would cover `.map`/`forEach` and imported lists.
    private def self.finale_expand(content : String, call_start : Int32, template : String) : Array(String)
      return [template] unless template.includes?("${")
      vars = template.scan(/\$\{([^}]*)\}/).map(&.[1].strip).uniq!
      return [] of String unless vars.size == 1 && vars[0].matches?(/\A[A-Za-z_$][\w$]*\z/)
      var = vars[0]
      values = nil.as(Array(String)?)
      content[0, call_start].scan(FINALE_FOR_OF_RE) do |loop_match|
        next unless loop_match[1].split(',').any? { |binding| binding.strip == var }
        body_close = find_matching_brace(content, loop_match.end(0) - 1)
        next unless body_close && body_close > call_start
        decl = content.match(/\b(?:const|let|var)\s+#{Regex.escape(loop_match[2])}(?:\s*:[^=\n]*)?\s*=\s*\[/) || next
        array_close = JSLiteralScanner.find_matching_bracket(content, decl.end(0) - 1) || next
        values = content[decl.end(0)...array_close]
          .scan(/(?:^|[{,\s])#{Regex.escape(var)}\s*:\s*['"]([^'"]*)['"]/).map(&.[1])
      end
      return [] of String unless values
      values.map { |value| template.gsub(/\$\{[^}]*\}/, value) }
    end

    private def self.push_unresolved_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      param = Param.new(name, "", type)
      param.add_tag(Tag.new("unresolved", "Key is a variable/constant identifier, not a string literal", "analyzer"))
      endpoint.push_param(param)
    end

    COMMENT_OPENER_RE = %r{/[/*]}

    # Replace JS/TS comments with whitespace of the same shape.
    # Preserves newlines and column offsets so downstream line/column
    # math (`controller_start_line`, regex `.begin(0)`, etc.) stays
    # accurate. Comment bodies are blanked to spaces so a commented-
    # out decorator like `// @Get('/old')` never matches the route
    # regex.
    #
    # Regex literals get their own state because their bodies routinely
    # contain quote characters (`str.replace(/'/g, "&#39;")`). Without it a
    # single such line inverted the string state for the rest of the file,
    # which cut both ways: real comments stopped being blanked, so
    # commented-out routes were reported as live endpoints, and real string
    # bodies were scanned as code, so a `//` or `/*` inside a string opened
    # a comment that swallowed every route below it.
    def self.strip_js_comments(content : String) : String
      # No `//` or `/*` anywhere means no comment: return the input as is.
      # Callers that hand already-blanked text on to `extract_routes` then
      # pay one scan instead of a second char-by-char rebuild.
      return content unless content.matches?(COMMENT_OPENER_RE)
      builder = String::Builder.new(content.bytesize)
      state = :code
      escaped = false
      in_char_class = false
      # Index of the last non-whitespace character emitted outside a comment.
      # Only consulted when a '/' shows up in code, so the backward word walk
      # it feeds costs nothing on the common path.
      last_sig = -1
      chars = content.chars
      i = 0
      len = chars.size

      while i < len
        char = chars[i]
        case state
        when :code
          if char == '/' && i + 1 < len
            nxt = chars[i + 1]
            if nxt == '/' && !JSLiteralScanner.url_slashes?(chars, i)
              state = :line_comment
              builder << "  "
              i += 2
              next
            elsif nxt == '*'
              state = :block_comment
              builder << "  "
              i += 2
              next
            end
          end
          if char == '`'
            # Shared with JSLiteralScanner so `${ … }` nesting (a template
            # inside a substitution) does not end the literal early.
            stop = JSLiteralScanner.template_literal_end(chars, len, i)
            (i...stop).each { |k| builder << chars[k] }
            last_sig = stop - 1
            i = stop
            next
          end
          if char == '/' && regex_literal_start?(chars, last_sig)
            state = :regex
            escaped = false
            in_char_class = false
          else
            if (char == '\'' || char == '"') && JSLiteralScanner.quote_opens_string?(chars, i)
              state = char == '\'' ? :single : :double
            end
          end
          builder << char
          last_sig = i unless char.whitespace?
        when :single, :double
          builder << char
          last_sig = i unless char.whitespace?
          if escaped
            # `\` + CRLF continues the line: the `\n` after the escaped `\r`
            # is escaped too.
            escaped = char == '\r'
          elsif char == '\\'
            escaped = true
          elsif (state == :single && char == '\'') ||
                (state == :double && char == '"') ||
                char == '\n' # string literals cannot span lines unescaped
            state = :code
          end
        when :regex
          builder << char
          last_sig = i unless char.whitespace?
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == '\n'
            # A JavaScript regex literal cannot span lines. Resyncing here
            # keeps a misjudged '/' (a JSX `</tag>`, say) from swallowing
            # the rest of the file.
            state = :code
          elsif char == '[' && !in_char_class
            in_char_class = true
          elsif char == ']' && in_char_class
            in_char_class = false
          elsif char == '/' && !in_char_class
            state = :code
          end
        when :line_comment
          if char == '\n'
            state = :code
            builder << '\n'
          else
            builder << ' '
          end
        when :block_comment
          if char == '*' && i + 1 < len && chars[i + 1] == '/'
            state = :code
            builder << "  "
            i += 2
            next
          end
          builder << (char == '\n' ? '\n' : ' ')
        end
        i += 1
      end

      builder.to_s
    end

    # 1-based line number for a CHAR index into `content`.
    def self.line_for_char_pos(content : String, pos : Int32) : Int32
      byte_pos = if content.bytesize == content.size
                   pos
                 else
                   content.char_index_to_byte_index(pos) || content.bytesize
                 end
      byte_pos = content.bytesize if byte_pos > content.bytesize
      content.to_slice[0, byte_pos].count('\n'.ord.to_u8) + 1
    end

    # Does the '/' the stripper is looking at open a regex literal?
    # `last_sig` is the index of the last non-whitespace character already
    # emitted as code. The decision itself belongs to JSLiteralScanner so
    # the stripper, the literal scanners and JSLexer cannot drift apart.
    private def self.regex_literal_start?(chars : Array(Char), last_sig : Int32) : Bool
      return false if last_sig < 0

      prev_char = chars[last_sig]
      prev_word = if prev_char.alphanumeric? || prev_char == '_' || prev_char == '$'
                    start = last_sig
                    while start > 0 && (chars[start - 1].alphanumeric? || chars[start - 1] == '_' || chars[start - 1] == '$')
                      start -= 1
                    end
                    String.build { |io| (start..last_sig).each { |k| io << chars[k] } }
                  else
                    ""
                  end

      JSLiteralScanner.regex_context?(prev_char, prev_word, last_sig > 0 ? chars[last_sig - 1] : nil)
    end

    # `delete req.query.lang` drops an input and `req.body.sort = 'asc'` or
    # `req.headers['x-tenant'] = 'default'` sets one; neither reads what the
    # client sent. `req.query.page ||= '1'` does read it, and is kept.
    REQUEST_WRITE_RE = /\bdelete\s+[\w$.?\[\]'"]+|(?<![\w$.])(?:req|request|ctx(?:\s*\.\s*request)?)\s*\??\.\s*(?:body|query|headers|cookies|params)\s*\??(?:\.\s*[\w$]+|\[[^\]]+\])\s*=(?![=>])/

    private def self.strip_request_writes(text : String) : String
      text.gsub(REQUEST_WRITE_RE, "")
    end

    # multer (and @koa/multer) middleware names the multipart file fields:
    # `upload.single('avatar')`, `upload.array('photos', 3)`,
    # `upload.fields([{ name: 'icon' }])`.
    MULTER_FIELD_RE  = /\.(?:single|array)\s*\(\s*['"`]([^'"`]+)['"`]/
    MULTER_FIELDS_RE = /\.fields\s*\(\s*\[([^\]]*)\]/
    MULTER_NAME_RE   = /\bname\s*:\s*['"`]([^'"`]+)['"`]/

    private def self.extract_multer_params(middleware : String, endpoint : Endpoint)
      middleware.scan(MULTER_FIELD_RE) { |m| endpoint.push_param(Param.new(m[1], "", "file")) }
      middleware.scan(MULTER_FIELDS_RE) do |m|
        m[1].scan(MULTER_NAME_RE) { |field| endpoint.push_param(Param.new(field[1], "", "file")) }
      end
    end

    def self.extract_body_params(handler_body : String, endpoint : Endpoint)
      handler_body = strip_request_writes(handler_body)
      # Look for req.body.X or const/let/var { X } = req.body
      # First check the destructuring pattern
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\??\.body/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
        end
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*ctx\.request\.body/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
        end
      end

      # Check direct property access: req.body.X / req.body?.X. A text or
      # array body's `length` and methods (`req.body.forEach(`) are not fields.
      handler_body.scan(/(?:req|request)\??\.body\??\.(\w+)\b(?!\s*\()/) do |match|
        next if match[1] == "length"
        endpoint.push_param(Param.new(match[1], "", "json"))
      end

      extract_multipart_params(handler_body, endpoint)

      # Check array access: req.body['X'] or req.body["X"]
      handler_body.scan(/(?:req|request)\??\.body(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "json"))
      end

      extract_destructured_prop_params(handler_body, "body", "json", endpoint)

      # Hono-style: const { X } = await c.req.json()
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.json\s*\(/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
        end
      end

      # Hono-style: const { X } = await c.req.parseBody()
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.parseBody\s*\(/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "form")) unless clean_param.empty?
        end
      end

      # Oak-style: const { X } = await ctx.request.body.json()
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+ctx\.request\.body\.json\s*\(/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
        end
      end
    end

    # formidable hands the parsed multipart body to a callback, `form.parse(req,
    # (err, fields, files) => …)`, or resolves it, `const [fields, files] =
    # await form.parse(req)`: `files.image` is an uploaded file, `fields.title`
    # a form field.
    MULTIPART_CALLBACK_RE = /\.parse\s*\(\s*(?:req|request)\s*,\s*(?:async\s+)?(?:function\s*[\w$]*\s*)?\(\s*[\w$]+\s*,\s*([\w$]+)\s*,\s*([\w$]+)\s*\)/
    MULTIPART_AWAIT_RE    = /(?:const|let|var)\s*\[\s*([\w$]+)\s*,\s*([\w$]+)\s*\]\s*=\s*await\s+[\w$.]+\.parse\s*\(\s*(?:req|request)\s*\)/

    private def self.extract_multipart_params(handler_body : String, endpoint : Endpoint)
      return unless handler_body.includes?(".parse")
      {MULTIPART_CALLBACK_RE, MULTIPART_AWAIT_RE}.each do |re|
        handler_body.scan(re) do |m|
          {m[1] => "form", m[2] => "file"}.each do |name, type|
            handler_body.scan(/(?<![\w$.])#{Regex.escape(name)}\s*\??\.\s*([A-Za-z_$][\w$]*)\b(?!\s*\()|(?<![\w$.])#{Regex.escape(name)}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |field|
              field_name = field[1]? || field[2]
              endpoint.push_param(Param.new(field_name, "", type)) unless field_name == "length"
            end
          end
        end
      end
    end

    def self.extract_query_params(handler_body : String, endpoint : Endpoint)
      handler_body = strip_request_writes(handler_body)
      # Look for destructuring: const/let/var { X } = req.query
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\??\.query/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "query")) unless clean_param.empty?
        end
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*ctx(?:\.request)?\.query/) do |match|
        params = match[1].split(",").map(&.strip)
        params.each do |param|
          clean_param = clean_destructured_param(param)
          endpoint.push_param(Param.new(clean_param, "", "query")) unless clean_param.empty?
        end
      end

      # Look for req.query.X / req.query?.X
      handler_body.scan(/(?:req|request)\??\.query\??\.(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      handler_body.scan(/(?:req|request)\??\.query(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      extract_destructured_prop_params(handler_body, "query", "query", endpoint)

      handler_body.scan(/ctx(?:\.request)?\.query\.(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      handler_body.scan(/ctx(?:\.request)?\.query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      # Hono-style: c.req.query('param')
      handler_body.scan(/\w+\.req\.query\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      # Hono-style: c.req.queries('param')
      handler_body.scan(/\w+\.req\.queries\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end

      # Oak/Fetch-API-style: ctx.request.url.searchParams.get('param')
      handler_body.scan(/ctx\.request\.url\.searchParams\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "query"))
      end
    end

    def self.extract_header_params(handler_body : String, endpoint : Endpoint)
      handler_body = strip_request_writes(handler_body)
      # Destructuring: const/let/var { authorization } = req.headers
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request|ctx(?:\.request)?)\??\.headers/) do |match|
        match[1].split(",").each do |param|
          clean_param = clean_destructured_param(param.strip)
          endpoint.push_param(Param.new(clean_param, "", "header")) unless clean_param.empty?
        end
      end

      # Express/Fastify-style: req.headers / req.header
      handler_body.scan(/(?:req|request)\??\.headers(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # req.headers["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/(?:req|request)\??\.headers(?:\?\.)?\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # req.headers[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "header")
      end
      handler_body.scan(/(?:req|request)\??\.headers\??\.(\w++)(?!\s*\()/) do |match| # req.headers.authorization
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/(?:req|request)\??\.headers\??\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # Fetch API: req.headers.get("x-token")
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/(?:req|request)\??\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # req.header("x-token")
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/(?:req|request)\??\.header\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # req.header(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "header")
      end
      handler_body.scan(/(?:req|request)\??\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # req.get("x-token")
        endpoint.push_param(Param.new(match[1], "", "header"))
      end

      extract_destructured_prop_params(handler_body, "headers", "header", endpoint)

      # Koa-style: ctx.headers / ctx.header / ctx.get
      handler_body.scan(/ctx\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # ctx.headers["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/ctx\.headers\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # ctx.headers[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "header")
      end
      handler_body.scan(/ctx\.header\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # ctx.header["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/ctx\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # ctx.get("x-token")
        endpoint.push_param(Param.new(match[1], "", "header"))
      end

      # Hono-style: c.req.header
      handler_body.scan(/\w+\.req\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # c.req.header("x-token")
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/\w+\.req\.header\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # c.req.header(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "header")
      end

      # Oak/Fetch-API-style: ctx.request.headers.get('x-token')
      handler_body.scan(/ctx\.request\.headers\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "header"))
      end
      handler_body.scan(/ctx\.request\.headers\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # unresolved
        push_unresolved_param(endpoint, match[1], "header")
      end
    end

    def self.extract_cookie_params(handler_body : String, endpoint : Endpoint)
      handler_body = strip_request_writes(handler_body)
      # Destructuring: const/let/var { token } = req.cookies
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request|ctx)\??\.cookies/) do |match|
        match[1].split(",").each do |param|
          clean_param = clean_destructured_param(param.strip)
          endpoint.push_param(Param.new(clean_param, "", "cookie")) unless clean_param.empty?
        end
      end

      # Express/Fastify-style: req.cookies
      handler_body.scan(/(?:req|request)\??\.cookies(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # req.cookies["session"]
        endpoint.push_param(Param.new(match[1], "", "cookie"))
      end
      handler_body.scan(/(?:req|request)\??\.cookies(?:\?\.)?\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # req.cookies[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "cookie")
      end
      handler_body.scan(/(?:req|request)\??\.cookies\??\.(\w++)(?!\s*\()/) do |match| # req.cookies.session
        endpoint.push_param(Param.new(match[1], "", "cookie"))
      end
      handler_body.scan(/(?:req|request)\??\.cookies\??\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # Bun: req.cookies.get("session")
        endpoint.push_param(Param.new(match[1], "", "cookie"))
      end

      extract_destructured_prop_params(handler_body, "cookies", "cookie", endpoint)

      # Koa-style: ctx.cookies.get
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # ctx.cookies.get("session")
        endpoint.push_param(Param.new(match[1], "", "cookie"))
      end
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # ctx.cookies.get(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "cookie")
      end

      # Hono-style: getCookie(c, 'name')
      handler_body.scan(/getCookie\s*\(\s*\w+\s*,\s*['"]([^'"]+)['"]\s*\)/) do |match| # getCookie(c, "name")
        endpoint.push_param(Param.new(match[1], "", "cookie"))
      end
      handler_body.scan(/getCookie\s*\(\s*\w+\s*,\s*([A-Za-z_$]\w*)\s*\)/) do |match| # getCookie(c, CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "cookie")
      end
    end

    def self.extract_path_params(handler_body : String, endpoint : Endpoint)
      handler_body = strip_request_writes(handler_body)
      # Destructuring: const/let/var { id } = req.params
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request|ctx)\??\.params/) do |match|
        match[1].split(",").each do |param|
          clean_param = clean_destructured_param(param.strip)
          endpoint.push_param(Param.new(clean_param, "", "path")) unless clean_param.empty?
        end
      end

      # Express/Fastify-style: req.params.X
      handler_body.scan(/(?:req|request)\??\.params\??\.(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end

      # Express/Fastify-style: req.params['X']
      handler_body.scan(/(?:req|request)\??\.params(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end

      extract_destructured_prop_params(handler_body, "params", "path", endpoint)

      # Hono-style: c.req.param('id')
      handler_body.scan(/\w+\.req\.param\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end

      # Koa-style: ctx.params.X / ctx.params['X']
      handler_body.scan(/ctx\.params\.(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      handler_body.scan(/ctx\.params\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Extracts parameters when a request property (`body`, `query`, `params`,
    # `headers`, `cookies`) is destructured in a handler's parameter signature
    # (`({ body: { name } }) => …`, `({ query, headers }) => { query.q }`) or
    # from `req`/`request` (`const { body, query } = req`).
    private def self.extract_destructured_prop_params(handler_body : String, prop : String, param_type : String, endpoint : Endpoint)
      return unless handler_body.includes?(prop) && handler_body.includes?('{')
      clauses = request_destructured_clauses(handler_body)
      return if clauses.empty?

      bound_vars = Set(String).new
      clauses.each do |clause|
        next unless clause.includes?(prop)
        clause.scan(/\b#{prop}\s*:\s*\{\s*([^}]+)\s*\}/) do |match|
          match[1].split(",").each do |param|
            clean_param = clean_destructured_param(param.strip)
            endpoint.push_param(Param.new(clean_param, "", param_type)) unless clean_param.empty?
          end
        end
        bound_vars << prop if clause.matches?(/\b#{prop}\b(?!\s*:)/)
        clause.scan(/\b#{prop}\s*:\s*([A-Za-z_$][\w$]*)\b/) do |match|
          bound_vars << match[1]
        end
      end

      bound_vars.each do |var_name|
        escaped = Regex.escape(var_name)
        handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*#{escaped}\b(?!\s*\.)/) do |match|
          match[1].split(",").each do |param|
            clean_param = clean_destructured_param(param.strip)
            endpoint.push_param(Param.new(clean_param, "", param_type)) unless clean_param.empty?
          end
        end
        handler_body.scan(/(?<![.\w$])#{escaped}\??\.(\w++)(?!\s*\()/) do |match|
          endpoint.push_param(Param.new(match[1], "", param_type))
        end
        handler_body.scan(/(?<![.\w$])#{escaped}(?:\?\.)?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
          endpoint.push_param(Param.new(match[1], "", param_type))
        end
      end
    end

    # Object-destructuring clauses `{ … }` that sit in a function signature's
    # first parameter (`({ query, headers }: Request, res: Response) => …`) or
    # destructure `req`/`request` directly (`const { body, query } = req`).
    private def self.request_destructured_clauses(handler_body : String) : Array(String)
      clauses = [] of String
      handler_body.scan(/\(\s*\{/) do |match|
        open_paren = match.byte_begin(0)
        open_brace = match.byte_end(0) - 1
        close_brace = JSLiteralScanner.find_matching_brace_at_byte(handler_body, open_brace) || next
        close_paren = JSLiteralScanner.find_matching_paren_at_byte(handler_body, open_paren) || next
        after_len = [handler_body.bytesize - close_paren - 1, 120].min
        after_paren = after_len > 0 ? handler_body.byte_slice(close_paren + 1, after_len) : ""
        before_paren = handler_body.byte_slice(0, open_paren)
        if after_paren.matches?(/\A(?:\s*:\s*[^{=;]+)?\s*=>/m) ||
           before_paren.matches?(/\bfunction(?:\s+[A-Za-z_$][\w$]*)?\s*\z/)
          clauses << handler_body.byte_slice(open_brace + 1, close_brace - open_brace - 1)
        end
      end
      handler_body.scan(/(?:const|let|var)\s*\{/) do |match|
        open_brace = match.byte_end(0) - 1
        close_brace = JSLiteralScanner.find_matching_brace_at_byte(handler_body, open_brace) || next
        after_len = [handler_body.bytesize - close_brace - 1, 120].min
        next unless after_len > 0
        after_brace = handler_body.byte_slice(close_brace + 1, after_len)
        if after_brace.matches?(/\A(?:\s*:\s*[^=;]+)?\s*=\s*(?:req|request|ctx(?:\.request)?)\b(?!\s*[\.\[])/)
          clauses << handler_body.byte_slice(open_brace + 1, close_brace - open_brace - 1)
        end
      end
      clauses
    end

    private def self.clean_destructured_param(param : String) : String
      clean_param = param.split("=").first.strip
      clean_param = clean_param.lchop("...").strip
      clean_param = clean_param.split(":").first.strip if clean_param.includes?(":")
      clean_param = clean_param[1..-2] if clean_param.size >= 2 &&
                                          ((clean_param.starts_with?("'") && clean_param.ends_with?("'")) ||
                                          (clean_param.starts_with?("\"") && clean_param.ends_with?("\"")))
      clean_param
    end

    # Extract static path declarations from JavaScript content
    # Returns array of hashes with static_path (URL prefix) and file_path (directory)
    # `framework` scopes the scan to one framework's static-mount idiom so a
    # framework analyzer running over a sibling project's file (every JS
    # analyzer walks all `.js`/`.ts` files) doesn't pick up another
    # framework's static declaration and re-emit it under the wrong tech.
    # `nil` runs every pattern (back-compat for un-scoped callers).
    STATIC_MOUNT_MARKER = Regex.union(
      ".use(", ".use (", ".register(", ".register (",
      "ServeStaticModule.forRoot", "serveStatic",
    )

    def self.extract_static_paths(content : String, framework : Symbol? = nil) : Array(Hash(String, String))
      static_paths = [] of Hash(String, String)

      # Cheap pre-filter: static-mount shapes use Express/Koa
      # `.use(...)`, Fastify `.register(...)`, NestJS
      # `ServeStaticModule.forRoot(...)`, or Restify `serveStatic(...)`.
      # Files without any of those markers cannot host one — skip the
      # regex scans on the vast majority of JS/TS files.
      return static_paths unless content_matches?(content, STATIC_MOUNT_MARKER)

      # Bundled/minified assets occasionally carry a `.use(`/`.register(`
      # substring from packed library code; never run the static-mount
      # regexes across a multi-megabyte single line (issue #1903).
      return static_paths if minified_content?(content)
      # The mount regexes read call arguments; a comment between them must
      # not hide the path (and a commented-out mount must not count).
      content = strip_js_comments(content)

      want_express = framework.nil? || framework == :express
      want_koa = framework.nil? || framework == :koa
      want_fastify = framework.nil? || framework == :fastify
      want_restify = framework.nil? || framework == :restify
      want_nestjs = framework.nil? || framework == :nestjs

      if want_express
        # Express patterns:
        # app.use('/static', express.static('public'))
        # app.use(express.static('public'))
        # router.use('/static', express.static('public'))
        content.scan(/(?:app|router|\w+)\.use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:express\.)?static\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[1],
              "file_path"   => match[2],
            }
          end
        end

        # app.use(express.static('public')) - no prefix, serves at root
        content.scan(/(?:app|router|\w+)\.use\s*\(\s*(?:express\.)?static\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
          if match.size >= 1
            static_paths << {
              "static_path" => "/",
              "file_path"   => match[1],
            }
          end
        end
      end

      if want_koa
        # Koa patterns with koa-static:
        # app.use(serve('public'))
        # app.use(serve('./static'))
        content.scan(/(?:app|router|\w+)\.use\s*\(\s*serve\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
          if match.size >= 1
            static_paths << {
              "static_path" => "/",
              "file_path"   => match[1],
            }
          end
        end

        # Koa patterns with koa-mount + koa-static:
        # app.use(mount('/static', serve('public')))
        content.scan(/(?:app|router|\w+)\.use\s*\(\s*mount\s*\(\s*['"]([^'"]+)['"]\s*,\s*serve\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[1],
              "file_path"   => match[2],
            }
          end
        end
      end

      if want_fastify
        # Fastify patterns:
        # fastify.register(require('@fastify/static'), { root: path.join(__dirname, 'public'), prefix: '/public/' })
        content.scan(/(?:fastify|app|server)\.register\s*\([^{]*\{[^}]*root\s*:\s*[^,}]*['"]([^'"]+)['"][^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[2],
              "file_path"   => match[1],
            }
          end
        end

        # Also try reverse order (prefix first, then root)
        content.scan(/(?:fastify|app|server)\.register\s*\([^{]*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"][^}]*root\s*:\s*[^,}]*['"]([^'"]+)['"]/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[1],
              "file_path"   => match[2],
            }
          end
        end
      end

      if want_restify
        # Restify patterns:
        # server.get(/\/public\/.*/, restify.plugins.serveStatic({directory: './public'}))
        # Try to extract the path from the regex pattern first
        content.scan(/(?:server|app)\.(?:get|use)\s*\(\s*\/\\?\/([^\/]+)\/[^,]*,\s*restify\.plugins\.serveStatic\s*\(\s*\{[^}]*directory\s*:\s*['"]([^'"]+)['"]/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => "/#{match[1]}",
              "file_path"   => match[2],
            }
          end
        end

        # Fallback: If no path in regex, use directory name as path
        content.scan(/(?:server|app)\.(?:get|use)\s*\([^,]*,\s*restify\.plugins\.serveStatic\s*\(\s*\{[^}]*directory\s*:\s*['"]\.?\/?([\w-]+)['"]\s*\}/) do |match|
          if match.size >= 1
            dir_name = match[1]
            # Check if this is already captured (exact match on directory name)
            unless static_paths.any? { |s| s["file_path"] == dir_name || s["file_path"].ends_with?("/#{dir_name}") }
              static_paths << {
                "static_path" => "/#{dir_name}",
                "file_path"   => match[1],
              }
            end
          end
        end
      end

      if want_nestjs
        # NestJS patterns typically use ServeStaticModule in app.module.ts
        # ServeStaticModule.forRoot({ rootPath: join(__dirname, '..', 'public'), serveRoot: '/static' })
        content.scan(/ServeStaticModule\.forRoot\s*\(\s*\{[^}]*rootPath\s*:[^,}]*['"]([^'"]+)['"][^}]*serveRoot\s*:\s*['"]([^'"]+)['"]/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[2],
              "file_path"   => match[1],
            }
          end
        end

        # Also try reverse order for NestJS
        content.scan(/ServeStaticModule\.forRoot\s*\(\s*\{[^}]*serveRoot\s*:\s*['"]([^'"]+)['"][^}]*rootPath\s*:[^,}]*['"]([^'"]+)['"]/) do |match|
          if match.size >= 2
            static_paths << {
              "static_path" => match[1],
              "file_path"   => match[2],
            }
          end
        end
      end

      static_paths
    end
  end
end
