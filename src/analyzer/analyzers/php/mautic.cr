require "../../engines/php_engine"
require "../../../minilexers/php_lexer"

module Analyzer::Php
  # Mautic registers routes in per-bundle `Config/config.php` arrays instead of
  # Symfony attributes:
  #
  #     'routes' => [
  #         'main'   => [ 'name' => ['path' => '/themes', 'controller' => '…'] ],
  #         'public' => [ … ],
  #         'api'    => [ 'name' => ['path' => '/files/{dir}', 'controller' => '…', 'method' => 'POST'] ],
  #     ]
  #
  # The `api` group is mounted under `/api` by `CoreBundle/Loader/RouteLoader`
  # (`$apiCollection->addPrefix('/api')`); `main`/`public` sit at the root.
  # Verbs come from the optional `'method'` key (`'GET|POST'`, pipe-separated),
  # defaulting to GET. Path params are already `{brace}`-style.
  class Mautic < PhpEngine
    GROUP_PREFIXES = {"main" => "", "public" => "", "api" => "/api"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.includes?("Config/config.php") && path.ends_with?(".php")

      begin
        content = read_file_content(path)
        return endpoints unless content.includes?("'routes'") || content.includes?("\"routes\"")

        lexer = Noir::PhpLexer.new(content)

        routes_open = find_key_array_open(content, lexer, "routes", 0, content.size)
        return endpoints unless routes_open
        routes_close = lexer.matching_delimiter(routes_open)
        return endpoints unless routes_close

        GROUP_PREFIXES.each do |group, prefix|
          group_open = find_key_array_open(content, lexer, group, routes_open + 1, routes_close)
          next unless group_open
          group_close = lexer.matching_delimiter(group_open)
          next unless group_close
          endpoints.concat(parse_group(content, lexer, group_open + 1, group_close, prefix, path))
        end
      rescue e
        logger.debug "Error analyzing Mautic config #{path}: #{e}"
      end

      endpoints
    end

    # Find `'<key>' => [` within `[from, to)` and return the index of the `[`,
    # verified to be real code (not a comment / heredoc).
    private def find_key_array_open(content : String, lexer : Noir::PhpLexer, key : String, from : Int32, to : Int32) : Int32?
      regex = Regex.new("['\"]#{Regex.escape(key)}['\"]\\s*=>\\s*\\[")
      pos = from
      while match = content.match(regex, pos)
        match_text = match[0]
        start = content.index(match_text, pos)
        break unless start && start < to
        bracket_pos = start + match_text.size - 1
        # Validate the `[` (a code char) rather than the key's opening quote,
        # which the lexer masks as string content — so a real `'routes' => [`
        # passes while one buried in a heredoc/comment (masked `[`) is rejected.
        return bracket_pos if lexer.in_code?(bracket_pos)
        pos = start + match_text.size
      end
      nil
    end

    # Parse the route entries of one group body (`[from, to)`). Each entry is
    # `'name' => ['path' => '…', 'controller' => '…', 'method' => '…']`; the
    # `'method'` of an entry is whatever lies between its `'path'` and the next
    # `'path'` (path always precedes method/controller in Mautic configs).
    private def parse_group(content : String, lexer : Noir::PhpLexer, from : Int32, to : Int32,
                            prefix : String, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      body = content[from...to]

      path_hits = [] of Tuple(Int32, String)
      pos = 0
      while match = body.match(/['"]path['"]\s*=>\s*['"]([^'"]+)['"]/, pos)
        start = body.index(match[0], pos)
        break unless start
        # Validate the `=>` operator (code) rather than the `'path'` opening
        # quote (masked string content) to keep heredoc/comment matches out.
        arrow = match[0].index("=>") || 0
        path_hits << {start, match[1]} if lexer.in_code?(from + start + arrow)
        pos = start + match[0].size
      end

      path_hits.each_with_index do |hit, i|
        rel_pos, route_path = hit
        next_pos = i + 1 < path_hits.size ? path_hits[i + 1][0] : body.size
        entry = body[rel_pos...next_pos]

        methods =
          if method_match = entry.match(/['"]method['"]\s*=>\s*['"]([^'"]+)['"]/)
            method_match[1].split('|').map(&.strip.upcase).reject(&.empty?)
          else
            ["GET"]
          end
        methods = ["GET"] if methods.empty?

        full_path = build_full_path(prefix, route_path)
        params = extract_brace_path_params(full_path)
        details = Details.new(PathInfo.new(path))

        methods.each do |method|
          endpoints << Endpoint.new(full_path, method, params, details.dup)
        end
      end

      endpoints
    end
  end
end
