require "../../engines/elixir_engine"

module Analyzer::Elixir
  class Plug < ElixirEngine
    def analyze_file(path : String) : Array(Endpoint)
      ext = File.extname(path)
      return [] of Endpoint unless ext == ".ex" || ext == ".exs"
      # Elixir convention: `*_test.exs` files are ExUnit test
      # modules. They register routes (often via inline
      # `Plug.Router`-using modules or `defmodule TestRouter do ... use
      # Phoenix.Router`) purely to exercise the framework; the routes
      # never serve real traffic. Phoenix's own repo and any
      # `phx.gen.auth` scaffold's tests trip this hard.
      return [] of Endpoint if test_only_path?(path)

      endpoints = [] of Endpoint
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        # A Phoenix router is owned by the Phoenix analyzer, which
        # understands `scope` prefixes, the `resources` macro, and the
        # controller/action mapping. The bare `get "/path"` regex here
        # would re-extract those same lines stripped of their scope
        # prefix and minus every `resources`-generated route — degraded
        # duplicates that pollute the result. Skip the file and let the
        # Phoenix analyzer handle it.
        next endpoints if phoenix_router?(content)
        analyze_content(content, path).each do |endpoint|
          endpoints << endpoint unless endpoint.method.empty?
        end
      end
      endpoints
    end

    # `use MyAppWeb, :router` (or, rarely, `use Phoenix.Router`) marks a
    # Phoenix router module. The Plug.Router DSL never uses either, so
    # this distinguishes the two even though both share `get`/`post`
    # route macros.
    private def phoenix_router?(content : String) : Bool
      content.includes?("Phoenix.Router") ||
        content.matches?(/\buse\s+[A-Z]\w*(?:\.[A-Z]\w*)*\s*,\s*:router\b/)
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Find all route blocks and extract params
      lines = content.lines
      # Elixir lets `@moduledoc` / `@doc` / `~S` / `~s` use either
      # triple-double (`\"\"\"`) or triple-single (`'''`) delimiters.
      # Phoenix's `verified_routes.ex` opens the module doc with
      # `~S'''` and embeds Phoenix.Router examples (`get \"/...\",
      # Ctrl, :show`) inside it — those would otherwise leak. Track
      # both delimiters independently so a `~H\"\"\"` template inside
      # a `~S'''` outer doc doesn't pop the outer state.
      in_triple_double = false
      in_triple_single = false
      lines.each_with_index do |line, index|
        if line.includes?("\"\"\"")
          line.scan(/"""/).size.times { in_triple_double = !in_triple_double }
          next
        end
        if line.includes?("'''")
          line.scan(/'''/).size.times { in_triple_single = !in_triple_single }
          next
        end
        next if in_triple_double || in_triple_single

        line_endpoints = line_to_endpoint(line.strip)
        line_endpoints.each do |endpoint|
          unless endpoint.method.empty?
            details = Details.new(PathInfo.new(file_path, index + 1))
            endpoint.details = details

            block_end = find_block_end(lines, index)

            params = extract_params_from_block(lines, index, endpoint.method, block_end)
            params.each { |param| endpoint.push_param(param) }

            attach_callees_from_block(endpoint, lines, index, block_end, file_path) if include_callee

            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # ExUnit's filename convention is rigid: every test module sits in
    # a file named `*_test.exs`, and `mix test` ignores anything else.
    # Skipping by suffix is safe because production code never adopts
    # that name.
    private def test_only_path?(path : String) : Bool
      File.basename(path).ends_with?("_test.exs")
    end

    def extract_params_from_block(lines : Array(String), start_index : Int32, method : String, block_end : Int32? = nil) : Array(Param)
      params = Array(Param).new
      seen_params = Set(String).new # Track seen params for O(1) lookup

      # Find the end of the current route block (find matching "end")
      end_index = block_end || find_block_end(lines, start_index)
      return params if end_index == -1

      # Extract parameters from the block content
      (start_index..end_index).each do |i|
        line = lines[i]

        # Extract query parameters (conn.query_params["param"] or conn.params["param"] for GET)
        line.scan(/conn\.query_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "query:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "query")
            seen_params << param_key
          end
        end

        # Extract params (could be query for GET or form for POST/PUT/PATCH)
        line.scan(/conn\.params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_type = (method == "GET") ? "query" : "form"
          param_key = "#{param_type}:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", param_type)
            seen_params << param_key
          end
        end

        # Extract body parameters (conn.body_params["param"] for POST/PUT/PATCH)
        line.scan(/conn\.body_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "form:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "form")
            seen_params << param_key
          end
        end

        # Extract header parameters (get_req_header(conn, "header-name"))
        line.scan(/get_req_header\(conn,\s*["']([^"']+)["']\)/) do |match|
          param_name = match[1]
          param_key = "header:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "header")
            seen_params << param_key
          end
        end

        # Extract cookie parameters (conn.cookies["cookie_name"])
        line.scan(/conn\.cookies\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "cookie:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "cookie")
            seen_params << param_key
          end
        end
      end

      params
    end

    private def attach_callees_from_block(endpoint : Endpoint,
                                          lines : Array(String),
                                          start_index : Int32,
                                          block_end : Int32?,
                                          file_path : String)
      return unless block_end
      return if block_end == -1 || block_end <= start_index

      body_lines = lines[(start_index + 1)...block_end]
      return if body_lines.empty?

      callees = Noir::ElixirCalleeExtractor.callees_for_lines(body_lines, file_path, start_index + 2)
      attach_elixir_callees(endpoint, callees)
    end

    def find_block_end(lines : Array(String), start_index : Int32) : Int32
      # Find the matching "end" for the route block starting with "do"
      return -1 if start_index >= lines.size

      # Check if the line has "do" keyword
      return -1 unless lines[start_index].includes?("do")

      depth = 1
      (start_index + 1...lines.size).each do |i|
        depth += elixir_block_depth_delta(lines[i].strip)
        return i if depth == 0
      end

      -1
    end

    # The route macro must start a fresh token. Without the
    # `(?:^|[^.\w])` guard the bare verb matched as a substring of any
    # identifier — `@temp_slot_options "TEMPORARY …"` read as an
    # `options` route, `Repo.delete "x"` as a `delete` route — flooding
    # non-router modules with junk endpoints. The captured path is also
    # required to start with `/`, because the Plug.Router DSL only ever
    # registers absolute paths; that single constraint drops the
    # remaining `get "true"`-style false positives.
    PLUG_ROUTE_MACROS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "patch"   => "PATCH",
      "delete"  => "DELETE",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "forward" => "FORWARD",
    }

    # Precompiled per-verb route regexes. `line_to_endpoint` runs once per
    # line of every `.ex` file, and `Regex.new` rebuilt these 8 PCRE2
    # patterns on every call — the same recompilation cost the Phoenix
    # analyzer carried. Build them once.
    PLUG_ROUTE_PATTERNS = PLUG_ROUTE_MACROS.keys.to_h do |verb|
      {verb, Regex.new("(?:^|[^.\\w])#{verb}\\s+[\"']([^\"']+)[\"']")}
    end

    def line_to_endpoint(line : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Match Plug.Router style route definitions, e.g. `get "/path", do: …`
      PLUG_ROUTE_MACROS.each do |verb, method|
        next unless line.includes?(verb)
        line.scan(PLUG_ROUTE_PATTERNS[verb]) do |match|
          path = match[1]
          endpoints << Endpoint.new(path, method) if plug_route_path?(path)
        end
      end

      # Match match statements with method patterns
      # match "/path", via: [:get, :post]
      if via_match = line.match(/(?:^|[^.\w])match\s+["\']([^"\']+)["\'][^:]*via:\s*\[([^\]]+)\]/)
        path = via_match[1]
        if plug_route_path?(path)
          via_match[2].scan(/:(\w+)/) do |method_match|
            endpoints << Endpoint.new(path, method_match[1].upcase)
          end
        end
      end

      # Match simple match statements (defaults to GET)
      unless line.includes?("via:")
        line.scan(/(?:^|[^.\w])match\s+["\']([^"\']+)["\']/) do |match|
          path = match[1]
          endpoints << Endpoint.new(path, "GET") if plug_route_path?(path)
        end
      end

      endpoints
    end

    # Plug.Router only registers absolute paths, so a captured value that
    # doesn't begin with `/` is a misfire on some other string literal.
    private def plug_route_path?(path : String) : Bool
      path.starts_with?('/')
    end
  end
end
