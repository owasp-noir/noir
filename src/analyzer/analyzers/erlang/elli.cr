require "../../../models/analyzer"
require "./erlang_helper"
require "set"

module Analyzer::Erlang
  # Elli has no router at all — an `elli_handler` callback module routes
  # by pattern-matching the method and the split path in its `handle/3`
  # function head:
  #
  #     handle(Req, _Args) ->
  #         handle(Req#req.method, elli_request:path(Req), Req).
  #
  #     handle('GET', [<<"hello">>, <<"world">>], _Req) ->
  #         {ok, [], <<"Hello World!">>};
  #     handle('POST', [<<"users">>], Req) ->
  #         ...
  #
  # Unlike Cowboy the verb is right there in the clause head, so no
  # cross-module lookup is needed.
  class Elli < Analyzer
    # The 2-arity `handle(Req, _Args)` dispatcher carries no path, so the
    # head must bind a list in slot 2 to count as a route.
    CLAUSE_REGEX = /^\s*handle\s*\(\s*(?:'([A-Za-z]+)'|<<\s*"([A-Za-z]+)"\s*>>|([A-Z_][A-Za-z0-9_]*))\s*,\s*\[([^\]]*)\]/
    NEXT_CLAUSE  = /^\s*handle\s*\(/

    BINARY_SEGMENT = /\A<<\s*"([^"]*)"\s*>>\z/
    VARIABLE       = /\A[A-Z][A-Za-z0-9_]*\z/

    HTTP_VERBS = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}

    GET_ARG_REGEX  = /elli_request:get_arg(?:_decoded)?\s*\(\s*<<\s*"([^"]+)"\s*>>/
    POST_ARG_REGEX = /elli_request:post_arg(?:_decoded)?\s*\(\s*<<\s*"([^"]+)"\s*>>/
    HEADER_REGEX   = /elli_request:get_header\s*\(\s*<<\s*"([^"]+)"\s*>>/
    BODY_REGEX     = /elli_request:(?:body|post_args)\s*\(/

    def analyze
      get_files_by_extension(".erl").each do |path|
        next if File.directory?(path)

        content = read_file_content(path)
        # Every Elli route clause is a `handle(` head; skip files without
        # one before paying for the comment strip.
        next unless content.includes?("handle(")
        next unless content.includes?("elli")

        process_file(path, Helper.strip_erlang_comments(content))
      end

      @result
    end

    private def process_file(path : String, content : String)
      lines = content.lines

      lines.each_with_index do |line, idx|
        m = line.match(CLAUSE_REGEX)
        next unless m

        verb = m[1]? || m[2]? || m[3]?
        next unless verb

        # `handle(Method, Path, Req)` — the dispatcher clause, or a
        # catch-all. Neither is a concrete route.
        method = verb.upcase
        next unless HTTP_VERBS.includes?(method)

        url, params = parse_pattern(m[4])
        body = clause_body(lines, idx)
        params.concat(extract_params(body, params))

        details = Details.new(PathInfo.new(path, idx + 1))
        @result << Endpoint.new(url, method, params, details)
      end
    end

    # Elli path patterns are lists of binary segments, optionally with a
    # `|Rest` tail: `[<<"users">>, Id]`, `[<<"static">>|_]`.
    private def parse_pattern(body : String) : Tuple(String, Array(Param))
      params = [] of Param
      seen = Set(String).new
      rendered = [] of String

      head, _, tail = body.partition('|')
      has_tail = !tail.strip.empty?

      head.split(',').each do |raw|
        segment = raw.strip
        next if segment.empty?

        if m = segment.match(BINARY_SEGMENT)
          literal = m[1]
          rendered << literal unless literal.empty?
          next
        end

        if segment == "_" || segment.starts_with?('_')
          rendered << "*"
          next
        end

        if segment.matches?(VARIABLE)
          # `Id` binds the segment; noir's convention is a lowercase
          # param name.
          name = segment.underscore
          rendered << ":#{name}"
          params << Param.new(name, "", "path") if seen.add?(name)
          next
        end

        rendered << segment
      end

      # A `|Rest` tail matches every remaining segment; `|_` discards
      # them, but either way the route covers deeper paths.
      rendered << "*" if has_tail

      url = rendered.empty? ? "/" : "/#{rendered.join("/")}"
      {url, params}
    end

    private def clause_body(lines : Array(String), start_idx : Int32) : String
      parts = [] of String
      parts << lines[start_idx]

      i = start_idx + 1
      while i < lines.size
        break if lines[i].matches?(NEXT_CLAUSE)
        parts << lines[i]
        i += 1
      end

      parts.join("\n")
    end

    private def extract_params(body : String, existing : Array(Param)) : Array(Param)
      params = [] of Param
      seen = Set(Tuple(String, String)).new
      existing.each { |param| seen.add({param.name, param.param_type}) }

      body.scan(GET_ARG_REGEX) do |m|
        name = m[1]
        params << Param.new(name, "", "query") if seen.add?({name, "query"})
      end

      body.scan(POST_ARG_REGEX) do |m|
        name = m[1]
        params << Param.new(name, "", "body") if seen.add?({name, "body"})
      end

      body.scan(HEADER_REGEX) do |m|
        name = m[1]
        params << Param.new(name, "", "header") if seen.add?({name, "header"})
      end

      if body.matches?(BODY_REGEX) && seen.add?({"body", "body"})
        params << Param.new("body", "", "body")
      end

      params
    end
  end
end
