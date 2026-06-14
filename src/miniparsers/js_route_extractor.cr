require "../models/endpoint"
require "../miniparsers/js_callee_extractor"
require "../minilexers/js_lexer"
require "../miniparsers/js_parser"
require "../models/code_locator"
require "../utils/url_path"
require "../utils/js_literal_scanner"
require "../analyzer/analyzers/javascript/express_constants"

module Noir
  # JSRouteExtractor provides a unified interface for extracting routes from JavaScript files
  class JSRouteExtractor
    # Import constants for key generation
    ROUTER_PREFIX_KEY = Analyzer::Javascript::ExpressConstants::ROUTER_PREFIX_KEY

    def self.extract_routes(file_path : String,
                            content : String? = nil,
                            debug : Bool = false,
                            *,
                            include_callees : Bool = false,
                            route_callees : Hash(String, Array(JSCalleeExtractor::Entry))? = nil) : Array(Endpoint)
      return [] of Endpoint unless File.exists?(file_path)

      begin
        content = content || File.read(file_path, encoding: "utf-8", invalid: :skip)

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
        parser = JSParser.new(content)
        route_patterns = parser.parse_routes
        callees_by_route = if include_callees
                             route_callees || JSCalleeExtractor.callees_for_routes(content, file_path)
                           else
                             {} of String => Array(JSCalleeExtractor::Entry)
                           end

        if debug && parser.hit_max_iterations?
          STDERR.puts "Warning: Maximum iterations reached in JS parser, parsing may be incomplete"
        end

        # No route patterns means the rest of this method has nothing
        # to emit — every downstream step (function_ranges build,
        # internal-mount scan, prefix propagation) exists to attribute
        # prefixes to routes the parser already found.
        return [] of Endpoint if route_patterns.empty?

        # Check if this file has a router prefix from cross-file mounting
        locator = CodeLocator.instance

        # Normalize file path to absolute path for consistent lookup
        absolute_file_path = File.expand_path(file_path)
        lookup_key = Analyzer::Javascript::ExpressConstants.file_key(absolute_file_path)
        # Use all() since routers can be mounted at multiple prefixes
        file_prefixes = locator.all(lookup_key)

        # Build function ranges to support function-scoped router prefixes
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
            match_start = m.begin(0)
            next unless match_start

            open_brace_idx = if kind == :arrow
                               arrow_idx = content.index("=>", match_start)
                               next unless arrow_idx
                               content.index("{", arrow_idx + 2)
                             else
                               param_start = content.index("(", match_start)
                               next unless param_start
                               param_end = find_matching_paren(content, param_start) || param_start
                               content.index("{", param_end + 1)
                             end

            next unless open_brace_idx
            close_brace_idx = find_matching_brace(content, open_brace_idx)
            next unless close_brace_idx
            function_ranges << {func_name, open_brace_idx, close_brace_idx}
            function_names.add(func_name)
          end
        end

        # Build internal mount relationships: parent function -> child function with prefix
        internal_mounts = [] of Tuple(String, String, String)
        function_ranges.each do |func_name, start_idx, end_idx|
          body = content[start_idx..end_idx]
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
          /\b\w+\.register\s*\(\s*(?:async\s+)?function\s*\([^)]*\)\s*\{/,
          /\b\w+\.register\s*\(\s*(?:async\s+)?\([^)]*\)\s*=>\s*\{/,
          /\b\w+\.register\s*\(\s*(?:async\s+)?\w+\s*=>\s*\{/,
        ]
        seen_anonymous_registers = Set(String).new

        anonymous_register_patterns.each do |register_pattern|
          content.scan(register_pattern) do |m|
            match_start = m.begin(0)
            next unless match_start

            register_paren_idx = content.index("(", match_start)
            open_brace_idx = content.index("{", match_start)
            next unless register_paren_idx && open_brace_idx

            close_brace_idx = find_matching_brace(content, open_brace_idx)
            close_paren_idx = find_matching_paren(content, register_paren_idx)
            next unless close_brace_idx && close_paren_idx
            next if close_brace_idx >= close_paren_idx

            trailer = content[(close_brace_idx + 1)...close_paren_idx]
            next unless trailer

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
          values = locator.all(func_key)
          if values.size > 0
            values.each do |prefix|
              prefixes_by_function[func_name] << prefix unless prefix.empty?
            end
          else
            value = locator.get(func_key)
            if value.is_a?(String) && !value.empty?
              prefixes_by_function[func_name] << value
            end
          end
        end

        # Seed same-file Fastify plugin registrations from top-level mounts.
        content.scan(/\b\w+\.register\s*\(\s*(\w+)\s*,\s*\{[^}]*prefix\s*:\s*['"]([^'"]+)['"]/) do |m|
          next unless m.size >= 3
          func_name = m[1]
          prefix = m[2]
          next unless function_names.includes?(func_name)
          prefixes_by_function[func_name] << prefix unless prefixes_by_function[func_name].includes?(prefix)
        end

        # Propagate prefixes through internal mounts with max iteration protection
        changed = true
        max_iterations = 100 # Prevent infinite loops in case of cyclic references
        iterations = 0
        while changed && iterations < max_iterations
          changed = false
          iterations += 1
          internal_mounts.each do |parent, child, mount_prefix|
            parent_prefixes = prefixes_by_function[parent]
            if parent_prefixes.empty? && !file_prefixes.empty?
              parent_prefixes = file_prefixes
            end
            parent_prefixes.each do |p|
              combined = URLPath.join(p, mount_prefix)
              unless prefixes_by_function[child].includes?(combined)
                prefixes_by_function[child] << combined
                changed = true
              end
            end
          end
        end

        endpoints = [] of Endpoint
        route_patterns.each do |pattern|
          # Apply cross-file router prefix if present (function-scoped first)
          prefixes = [] of String
          if pattern.start_pos >= 0
            # Find all functions containing this route, sorted by span (innermost first)
            containing_functions = [] of Tuple(String, Int32)
            function_ranges.each do |func_name, start_idx, end_idx|
              if start_idx <= pattern.start_pos && pattern.start_pos <= end_idx
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
          if prefixes.empty? && pattern.start_pos >= 0
            containing_registers = [] of Tuple(String, Int32)
            anonymous_register_ranges.each do |start_idx, end_idx, prefix|
              if start_idx <= pattern.start_pos && pattern.start_pos <= end_idx
                containing_registers << {prefix, end_idx - start_idx}
              end
            end
            unless containing_registers.empty?
              containing_registers.sort_by! { |_, span| span }
              anonymous_prefix = containing_registers.first[0]
              prefixes = [anonymous_prefix]
            end
          end
          if prefixes.empty? && !file_prefixes.empty?
            prefixes = file_prefixes
          end
          prefixes = [""] if prefixes.empty?

          # Normalize HTTP method (e.g., DEL -> DELETE)
          normalized_method = normalize_http_method(pattern.method)

          # Convert byte offset to line number
          line_number = if pattern.start_pos >= 0
                          content.to_slice[0, pattern.start_pos].count('\n'.ord.to_u8) + 1
                        else
                          1
                        end
          route_details = Details.new(PathInfo.new(file_path, line_number))

          # Handle router.all by expanding to all HTTP methods
          prefixes.each do |prefix|
            path_with_prefix = prefix.empty? ? pattern.path : URLPath.join(prefix, pattern.path)

            if normalized_method == "ALL"
              all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
              all_methods.each do |method|
                endpoint = Endpoint.new(path_with_prefix, method, route_details)

                # Add path parameters detected in the URL
                pattern.params.each do |param|
                  endpoint.push_param(param)
                end

                # Extract other parameters like body, query, etc. from the content around this route
                extract_params_from_context(content, pattern, endpoint)
                attach_callees(endpoint, callees_by_route, normalized_method, pattern.raw_path, line_number)

                endpoints << endpoint
              end
            else
              endpoint = Endpoint.new(path_with_prefix, normalized_method, route_details)

              # Add path parameters detected in the URL
              pattern.params.each do |param|
                endpoint.push_param(param)
              end

              # Extract other parameters like body, query, etc. from the content around this route
              extract_params_from_context(content, pattern, endpoint)
              attach_callees(endpoint, callees_by_route, normalized_method, pattern.raw_path, line_number)

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
    # cross-file router prefix table). Substring-checking is millions
    # of times cheaper than tokenizing the file.
    PARSER_ROUTE_CALL_HINTS = [
      ".get(", ".post(", ".put(", ".delete(", ".patch(",
      ".options(", ".head(", ".all(",
      ".route(", ".register(", ".use(",
      ".get (", ".post (", ".put (", ".delete (", ".patch (",
      ".options (", ".head (", ".all (",
      ".route (", ".register (", ".use (",
    ]

    BRACKET_ROUTE_CALL_PATTERN  = /\[\s*['"](?:get|post|put|delete|del|patch|options|head|all)['"]\s*\]\s*\(/i
    FLEXIBLE_ROUTE_CALL_PATTERN = /\.(?:\s|\n|\r)*(?:get|post|put|delete|del|patch|options|head|all|route|register|use)(?:\s|\n|\r)*\(/i

    def self.route_call_candidate?(content : String) : Bool
      PARSER_ROUTE_CALL_HINTS.any? { |hint| content.includes?(hint) } ||
        content.matches?(BRACKET_ROUTE_CALL_PATTERN) ||
        content.matches?(FLEXIBLE_ROUTE_CALL_PATTERN)
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
    #   2. the file's average line length reaches
    #      MINIFIED_AVG_LINE_THRESHOLD — long lines dominate, newline
    #      density is low.
    # webpack/rollup output and `*.min.js` satisfy both (the whole file
    # is one or a few enormous lines); a route module with a 7 KB inline
    # payload amid dozens of short route lines satisfies neither, so its
    # real endpoints survive. Skipping such a file is purely a parser
    # optimization — small files lex fast regardless — so there is no
    # need to skip one merely because it embeds a fat literal.
    def self.minified_content?(content : String,
                               line_threshold : Int32 = MINIFIED_LINE_THRESHOLD,
                               avg_threshold : Int32 = MINIFIED_AVG_LINE_THRESHOLD) : Bool
      bytesize = content.bytesize
      # Too small to contain a long-enough line — also skips the scan on
      # the vast majority of source files for free.
      return false if bytesize < line_threshold

      longest = 0
      run = 0
      lines = 1
      content.each_byte do |byte|
        if byte == 0x0a_u8 # '\n'
          longest = run if run > longest
          run = 0
          lines += 1
        else
          run += 1
        end
      end
      longest = run if run > longest

      return false if longest < line_threshold
      (bytesize // lines) >= avg_threshold
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
      "-spec.",
      "-test.",
      # tsd / expect-type style type-only test files. fastify's
      # `test/types/*.test-d.ts` suites register sample routes purely
      # to assert their inferred typings — no production endpoints,
      # but the JSParser pre-filter sees the same `app.get(`/`.post(`
      # shapes.
      ".test-d.",
    ]

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
    def self.test_stub_only?(file_path : String, content : String,
                             include_client_frameworks : Bool = true) : Bool
      return true if TEST_STUB_FILENAME_MARKERS.any? { |m| file_path.includes?(m) }
      return true if STRICT_TEST_PATH_MARKERS.any? { |m| file_path.includes?(m) }
      has_library = TEST_STUB_LIBRARY_MARKERS.any? { |m| content.includes?(m) } ||
                    (include_client_frameworks && CLIENT_SIDE_FRAMEWORK_MARKERS.any? { |m| content.includes?(m) })
      has_path_marker = TEST_STUB_PATH_MARKERS.any? { |m| file_path.includes?(m) }
      return false unless has_library || has_path_marker
      HTTP_SERVER_LIBRARY_MARKERS.none? { |m| content.includes?(m) }
    end

    def self.attach_callees(endpoint : Endpoint,
                            callees_by_route : Hash(String, Array(JSCalleeExtractor::Entry)),
                            method : String,
                            path : String,
                            line : Int32)
      callees = callees_by_route[JSCalleeExtractor.route_key(method, path, line)]?
      return unless callees

      callees.each do |name, callee_path, callee_line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
      end
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
      when "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"
        return method
      end

      # Return the original (uppercased) method if no specific normalization needed
      method
    end

    # Memoizes the direct-call patterns built in extract_params_from_context;
    # the alternation is derived from the route's HTTP method, so the key set
    # is tiny. Fibers are cooperative (no preview_mt), so the plain Hash is
    # safe under the analyzers' parallel file scans.
    @@direct_call_res = Hash(String, Regex).new

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

    def self.extract_params_from_context(content : String, pattern : JSRoutePattern, endpoint : Endpoint)
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
      if pattern.start_pos >= 0
        start_idx = pattern.start_pos
        search_window = content[start_idx, Math.min(content.size - start_idx, 500)]
        method_alternation = method_variations.map { |method| Regex.escape(method) }.join("|")
        # Memoized — method_alternation has ~8 distinct values, and an
        # interpolated regex literal would recompile (full PCRE2 compile)
        # once per endpoint.
        direct_call_pattern = @@direct_call_res.fetch(method_alternation) do
          @@direct_call_res[method_alternation] = /\.\s*(?:#{method_alternation})\s*\(/i
        end
        if direct_match = search_window.match(direct_call_pattern)
          candidate_idx = start_idx + (direct_match.begin(0) || 0)
          open_paren = content.index("(", candidate_idx)
          if open_paren
            arg_window = content[open_paren, Math.min(content.size - open_paren, 300)]
            if quoted_substring?(arg_window, lookup_path)
              idx = candidate_idx
              found_declaration = "direct"
            end
          end
        end
      end

      route_declarations.each do |declaration|
        break if idx

        found_idx = content.index(declaration)
        if found_idx
          idx = found_idx
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
          if named_match = content.match(named_route_pattern)
            idx = named_match.begin(0)
            found_declaration = method
            break
          end
        end
      end

      return unless idx

      # If we found a route() declaration, we need to find the specific .method() call after it
      if found_declaration.starts_with?("route(")
        # Look for the .method( pattern after the route declaration
        search_start = idx
        method_variations.each do |method|
          method_idx = content.index(".#{method}(", search_start)
          if method_idx && method_idx > idx && (method_idx - idx) < 200
            idx = method_idx
            break
          end
        end
      end

      # Find the bounds of the method call arguments to keep the search scoped
      open_paren_idx = content.index("(", idx)
      return unless open_paren_idx
      close_paren_idx = find_matching_paren(content, open_paren_idx)
      return unless close_paren_idx

      args_start = open_paren_idx + 1
      args_end = close_paren_idx - 1
      return if args_end < args_start

      args_slice = content[args_start..args_end]
      function_idx = args_slice.rindex(/\bfunction\b/)
      arrow_idx = args_slice.rindex("=>")

      anchor_idx = nil
      anchor_kind = :function
      if function_idx && arrow_idx
        if function_idx > arrow_idx
          anchor_idx = function_idx
          anchor_kind = :function
        else
          anchor_idx = arrow_idx
          anchor_kind = :arrow
        end
      elsif function_idx
        anchor_idx = function_idx
        anchor_kind = :function
      elsif arrow_idx
        anchor_idx = arrow_idx
        anchor_kind = :arrow
      end

      return unless anchor_idx

      anchor_abs = args_start + anchor_idx
      open_brace_idx = content.index("{", anchor_abs)
      return unless open_brace_idx && open_brace_idx < close_paren_idx

      # Avoid treating concise arrow returning object literals as a block body.
      if anchor_kind == :arrow
        prev = open_brace_idx - 1
        while prev > anchor_abs && content[prev].whitespace?
          prev -= 1
        end
        return if prev >= anchor_abs && content[prev] == '('
      end

      # Extract the handler function body
      # (This is a simplified approach - a more robust approach would count braces)
      close_brace_idx = find_matching_brace(content, open_brace_idx)
      return unless close_brace_idx && close_brace_idx < close_paren_idx

      handler_body = content[open_brace_idx..close_brace_idx]

      # Now analyze the handler body for req.body, req.query, etc.
      extract_body_params(handler_body, endpoint)
      extract_query_params(handler_body, endpoint)
      extract_header_params(handler_body, endpoint)
      extract_cookie_params(handler_body, endpoint)
      extract_path_params(handler_body, endpoint)
    end

    # Delegate to JSLiteralScanner for literal-aware brace matching
    def self.find_matching_brace(content : String, open_brace_idx : Int32) : Int32?
      JSLiteralScanner.find_matching_brace(content, open_brace_idx)
    end

    # Delegate to JSLiteralScanner for literal-aware paren matching
    def self.find_matching_paren(content : String, open_paren_idx : Int32) : Int32?
      JSLiteralScanner.find_matching_paren(content, open_paren_idx)
    end

    private def self.push_unresolved_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      param = Param.new(name, "", type)
      param.add_tag(Tag.new("unresolved", "Key is a variable/constant identifier, not a string literal", "analyzer"))
      endpoint.push_param(param)
    end

    # Replace JS/TS comments with whitespace of the same shape.
    # Preserves newlines and column offsets so downstream line/column
    # math (`controller_start_line`, regex `.begin(0)`, etc.) stays
    # accurate. Comment bodies are blanked to spaces so a commented-
    # out decorator like `// @Get('/old')` never matches the route
    # regex.
    def self.strip_js_comments(content : String) : String
      builder = String::Builder.new(content.bytesize)
      state = :code
      escaped = false
      chars = content.chars
      i = 0
      len = chars.size

      while i < len
        char = chars[i]
        case state
        when :code
          if char == '/' && i + 1 < len
            nxt = chars[i + 1]
            if nxt == '/'
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
          case char
          when '\''
            state = :single
          when '"'
            state = :double
          when '`'
            state = :template
          end
          builder << char
        when :single, :double, :template
          builder << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif (state == :single && char == '\'') ||
                (state == :double && char == '"') ||
                (state == :template && char == '`')
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

    def self.extract_body_params(handler_body : String, endpoint : Endpoint)
      # Look for req.body.X or const/let/var { X } = req.body
      # First check the destructuring pattern
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\.body/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*ctx\.request\.body/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      # Check direct property access: req.body.X
      handler_body.scan(/(?:req|request)\.body\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "json"))
        end
      end

      # Check array access: req.body['X'] or req.body["X"]
      handler_body.scan(/(?:req|request)\.body\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "json"))
        end
      end

      # Hono-style: const { X } = await c.req.json()
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.json\s*\(/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "json")) unless clean_param.empty?
          end
        end
      end

      # Hono-style: const { X } = await c.req.parseBody()
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*await\s+\w+\.req\.parseBody\s*\(/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "form")) unless clean_param.empty?
          end
        end
      end
    end

    def self.extract_query_params(handler_body : String, endpoint : Endpoint)
      # Look for destructuring: const/let/var { X } = req.query
      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*(?:req|request)\.query/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "query")) unless clean_param.empty?
          end
        end
      end

      handler_body.scan(/(?:const|let|var)\s*\{\s*([^}]+)\s*\}\s*=\s*ctx(?:\.request)?\.query/) do |match|
        if match.size > 0
          params = match[1].split(",").map(&.strip)
          params.each do |param|
            clean_param = clean_destructured_param(param)
            endpoint.push_param(Param.new(clean_param, "", "query")) unless clean_param.empty?
          end
        end
      end

      # Look for req.query.X
      handler_body.scan(/(?:req|request)\.query\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end

      handler_body.scan(/(?:req|request)\.query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end

      handler_body.scan(/ctx(?:\.request)?\.query\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end

      handler_body.scan(/ctx(?:\.request)?\.query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end

      # Hono-style: c.req.query('param')
      handler_body.scan(/\w+\.req\.query\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end

      # Hono-style: c.req.queries('param')
      handler_body.scan(/\w+\.req\.queries\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "query"))
        end
      end
    end

    def self.extract_header_params(handler_body : String, endpoint : Endpoint)
      # Express/Fastify-style: req.headers / req.header
      handler_body.scan(/(?:req|request)\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # req.headers["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.headers\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # req.headers[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "header") if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.headers\.(\w+)/) do |match| # req.headers.authorization
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # req.header("x-token")
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.header\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # req.header(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "header") if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # req.get("x-token")
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end

      # Koa-style: ctx.headers / ctx.header / ctx.get
      handler_body.scan(/ctx\.headers\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # ctx.headers["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/ctx\.headers\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # ctx.headers[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "header") if match.size > 0
      end
      handler_body.scan(/ctx\.header\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # ctx.header["x-token"]
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/ctx\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # ctx.get("x-token")
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end

      # Hono-style: c.req.header
      handler_body.scan(/\w+\.req\.header\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # c.req.header("x-token")
        endpoint.push_param(Param.new(match[1], "", "header")) if match.size > 0
      end
      handler_body.scan(/\w+\.req\.header\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # c.req.header(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "header") if match.size > 0
      end
    end

    def self.extract_cookie_params(handler_body : String, endpoint : Endpoint)
      # Express/Fastify-style: req.cookies
      handler_body.scan(/(?:req|request)\.cookies\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match| # req.cookies["session"]
        endpoint.push_param(Param.new(match[1], "", "cookie")) if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.cookies\s*\[\s*([A-Za-z_$]\w*)\s*\]/) do |match| # req.cookies[CONST] — unresolved
        push_unresolved_param(endpoint, match[1], "cookie") if match.size > 0
      end
      handler_body.scan(/(?:req|request)\.cookies\.(\w+)/) do |match| # req.cookies.session
        endpoint.push_param(Param.new(match[1], "", "cookie")) if match.size > 0
      end

      # Koa-style: ctx.cookies.get
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match| # ctx.cookies.get("session")
        endpoint.push_param(Param.new(match[1], "", "cookie")) if match.size > 0
      end
      handler_body.scan(/ctx\.cookies\.get\s*\(\s*([A-Za-z_$]\w*)\s*\)/) do |match| # ctx.cookies.get(CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "cookie") if match.size > 0
      end

      # Hono-style: getCookie(c, 'name')
      handler_body.scan(/getCookie\s*\(\s*\w+\s*,\s*['"]([^'"]+)['"]\s*\)/) do |match| # getCookie(c, "name")
        endpoint.push_param(Param.new(match[1], "", "cookie")) if match.size > 0
      end
      handler_body.scan(/getCookie\s*\(\s*\w+\s*,\s*([A-Za-z_$]\w*)\s*\)/) do |match| # getCookie(c, CONST) — unresolved
        push_unresolved_param(endpoint, match[1], "cookie") if match.size > 0
      end
    end

    def self.extract_path_params(handler_body : String, endpoint : Endpoint)
      # Express/Fastify-style: req.params.X
      handler_body.scan(/(?:req|request)\.params\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "path")) unless endpoint.params.any? { |p| p.name == match[1] && p.param_type == "path" }
        end
      end

      # Express/Fastify-style: req.params['X']
      handler_body.scan(/(?:req|request)\.params\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "path")) unless endpoint.params.any? { |p| p.name == match[1] && p.param_type == "path" }
        end
      end

      # Hono-style: c.req.param('id')
      handler_body.scan(/\w+\.req\.param\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "path")) unless endpoint.params.any? { |p| p.name == match[1] && p.param_type == "path" }
        end
      end

      # Koa-style: ctx.params.X
      handler_body.scan(/ctx\.params\.(\w+)/) do |match|
        if match.size > 0
          endpoint.push_param(Param.new(match[1], "", "path")) unless endpoint.params.any? { |p| p.name == match[1] && p.param_type == "path" }
        end
      end
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
    def self.extract_static_paths(content : String, framework : Symbol? = nil) : Array(Hash(String, String))
      static_paths = [] of Hash(String, String)

      # Cheap pre-filter: static-mount shapes use Express/Koa
      # `.use(...)`, Fastify `.register(...)`, NestJS
      # `ServeStaticModule.forRoot(...)`, or Restify `serveStatic(...)`.
      # Files without any of those markers cannot host one — skip the
      # regex scans on the vast majority of JS/TS files.
      return static_paths unless content.includes?(".use(") || content.includes?(".use (") ||
                                 content.includes?(".register(") || content.includes?(".register (") ||
                                 content.includes?("ServeStaticModule.forRoot") ||
                                 content.includes?("serveStatic")

      # Bundled/minified assets occasionally carry a `.use(`/`.register(`
      # substring from packed library code; never run the static-mount
      # regexes across a multi-megabyte single line (issue #1903).
      return static_paths if minified_content?(content)

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
