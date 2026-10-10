require "../../engines/scala_engine"

module Analyzer::Scala
  # Finatra HTTP controllers: `get("/users/:id") { request: Request => ... }`
  # inside a class extending `Controller`, with `prefix("/x") { ... }` blocks
  # composing a path prefix.
  # ponytail: `router.add("/v1", ...)` registration prefixes and typed request
  # case classes (`@RouteParam`/`@QueryParam`) are not followed yet.
  class Finatra < ScalaEngine
    analyzer_for "scala_finatra"

    CONTROLLER_RE = /\bextends\s+(?:[\w.]+\.)?Controller\b/
    ROUTE_RE      = /(?:(?<![.\w])|(?<=\]\.))(get|post|put|patch|delete|head|options|any)\s*(?:\[[^(]*\])?\s*\(\s*"([^"]*)"/
    PREFIX_RE     = /(?:(?<![.\w])|(?<=\]\.))prefix\s*\(\s*"([^"]*)"/
    # `request.params("q")`, any `ParamMap` accessor (`params.get`,
    # `params.getInt`, ...) and Finagle's `getParam` / `getIntParam` family.
    PARAM_READ_RE = /request\.(?:params(?:\.\w+)?|get(?:Int|Long|Short|Boolean)?Param)\s*\(\s*"([^"]+)"/

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint if sbt_test_path?(path)
      content = read_file_content(path)
      return [] of Endpoint unless content.includes?("com.twitter.finatra.http")

      endpoints = [] of Endpoint
      lexer = scala_lexer(content)
      lines = scala_code_text(lexer).split('\n')
      code = lexer.code_lines
      # Open `prefix` blocks as {segment, last line}; routes only count inside
      # a controller class body.
      prefixes = [] of Tuple(String, Int32)
      controller_end = -1

      code.each_with_index do |line, index|
        prefixes.reject! { |entry| entry[1] < index }
        if index > controller_end && line.matches?(CONTROLLER_RE)
          # scalafmt / Allman wraps put the body `{` a line or two below
          # `extends Controller`.
          controller_end = (index...Math.min(index + 4, lines.size)).each do |j|
            if block = extract_scala_brace_block_with_end(lines, j)
              break block[2]
            end
          end || -1
          next
        end
        next if index > controller_end

        if m = line.match(PREFIX_RE)
          if block = extract_scala_brace_block_with_end(lines, index)
            prefixes << {m[1], block[2]}
          end
        elsif m = line.match(ROUTE_RE)
          url = prefixes.reduce("") { |acc, entry| Noir::URLPath.join(acc, entry[0]) }
          url = Noir::URLPath.join(url, m[2])
          endpoint = Endpoint.new(url, m[1].upcase, Details.new(PathInfo.new(path, index + 1)))
          url.scan(/:(\w+|\*)/) { |pm| endpoint.push_param(Param.new(pm[1], "", "path")) }
          if block = extract_scala_brace_block(lines, index)
            block[0].scan(PARAM_READ_RE) do |pm|
              next if endpoint.params.any? { |p| p.name == pm[1] }
              endpoint.push_param(Param.new(pm[1], "", "query"))
            end
            attach_scala_callees(endpoint, Noir::ScalaCalleeExtractor.callees_for_body(block[0], path, block[1])) if callees_needed?
          end
          endpoints << endpoint
        end
      end

      endpoints
    end
  end
end
