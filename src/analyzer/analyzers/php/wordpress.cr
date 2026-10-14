require "../../engines/php_engine"
require "../../../utils/top_level_split"

module Analyzer::Php
  # WordPress attack-surface extractor.
  #
  # WordPress does not expose a conventional route table; its
  # HTTP surface is registered imperatively through a handful of
  # well-known APIs:
  #
  #   * REST API   — `register_rest_route( $namespace, $route, $args )`
  #                  served under `/wp-json/{namespace}/{route}`.
  #   * Admin AJAX — `add_action( 'wp_ajax_{action}', ... )` and the
  #                  public `wp_ajax_nopriv_{action}` variant, dispatched
  #                  by `/wp-admin/admin-ajax.php?action={action}`.
  #   * Admin POST — `add_action( 'admin_post_{action}', ... )` /
  #                  `admin_post_nopriv_{action}`, dispatched by
  #                  `/wp-admin/admin-post.php?action={action}`.
  class Wordpress < PhpEngine
    analyzer_for "php_wordpress"

    ADMIN_AJAX_PATH = "/wp-admin/admin-ajax.php"
    ADMIN_POST_PATH = "/wp-admin/admin-post.php"

    # WordPress admin-ajax / admin-post dispatch on `$_REQUEST['action']`,
    # so both verbs are valid entry points.
    DISPATCH_METHODS = ["GET", "POST"]

    ALL_HTTP_VERBS = ["GET", "POST", "PUT", "PATCH", "DELETE"]

    # `WP_REST_Server::` method-group constants → concrete HTTP verbs.
    REST_METHOD_CONSTANTS = {
      "READABLE"   => ["GET"],
      "CREATABLE"  => ["POST"],
      "EDITABLE"   => ["POST", "PUT", "PATCH"],
      "DELETABLE"  => ["DELETE"],
      "ALLMETHODS" => ["GET", "POST", "PUT", "PATCH", "DELETE"],
    }

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".php")

      content = read_file_content(path)
      rest = content.includes?("register_rest_route")
      hooks = content.includes?("wp_ajax_") || content.includes?("admin_post_")
      return endpoints unless rest || hooks

      content = php_code(content)
      endpoints.concat(analyze_rest_routes(content, path)) if rest
      endpoints.concat(analyze_action_hooks(content, path)) if hooks

      endpoints
    end

    # -- REST API --------------------------------------------------------

    private def analyze_rest_routes(content : String, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      properties = string_properties(content)
      offset = 0
      while call_start = content.index("register_rest_route", offset)
        paren_open = content.index('(', call_start)
        paren_close = paren_open ? find_matching_paren(content, paren_open) : nil

        if paren_open && paren_close
          # Advance past the whole balanced call for the next iteration.
          offset = paren_close + 1
          args = content[(paren_open + 1)...paren_close]

          parts = split_top_level_args(args)
          # The namespace/route are the first two *positional* args, each
          # string literals, `$this->prop` (a WP_REST_Controller's
          # `protected $namespace = '...'`) or a `.` concatenation of those.
          # Anything else can't be resolved statically — skip rather than emit
          # a bogus URL such as /wp-json/books/{id}/GET (which is what naively
          # scanning for the first two literals anywhere would produce).
          namespace = parts[0]?.try { |arg| resolve_string_expr(arg, properties) }
          route = parts[1]?.try { |arg| resolve_string_expr(arg, properties) }
          if namespace && route
            full_path = build_rest_path(namespace, route)
            path_params = extract_wp_path_params(full_path)

            rest_handlers(parts[2]? || "").each do |method, arg_names|
              params = path_params.dup
              type = method == "GET" || method == "DELETE" ? "query" : "form"
              arg_names.each do |name|
                params << Param.new(name, "", type) unless params.any? { |param| param.name == name }
              end
              endpoints << Endpoint.new(full_path, method, params, details.dup)
            end
          end
        else
          # Malformed/unbalanced call — skip past this occurrence so the
          # scan makes progress instead of re-matching the same position.
          offset = call_start + "register_rest_route".size
        end
      end

      endpoints
    end

    # The verbs a route's third argument registers, each with the `'args'`
    # names its handler declares. That argument is one handler array or an
    # array of them, one per verb group.
    private def rest_handlers(handlers_arg : String) : Hash(String, Array(String))
      handlers = [handlers_arg]
      if body = php_array_body(handlers_arg)
        elements = split_top_level_args(body).map(&.strip).reject(&.empty?)
        handlers = elements if !elements.empty? && elements.all? { |element| php_array_body(element) }
      end

      result = {} of String => Array(String)
      handlers.each do |handler|
        methods = extract_rest_methods(handler)
        methods = ["GET"] if methods.empty?
        names = rest_arg_names(handler)
        methods.each { |method| (result[method] ||= [] of String).concat(names) }
      end
      result
    end

    REST_ARGS_KEY_RE = /\A['"]args['"]\s*=>\s*/
    ARRAY_KEY_RE     = /\A['"]([^'"]+)['"]\s*=>/

    # Keys of a handler's `'args' => array( 'per_page' => …, … )`.
    private def rest_arg_names(handler : String) : Array(String)
      body = php_array_body(handler)
      return [] of String unless body
      split_top_level_args(body).each do |element|
        element = element.strip
        next unless key = element.match(REST_ARGS_KEY_RE)
        args_body = php_array_body(element[key.end(0)..])
        return [] of String unless args_body
        return split_top_level_args(args_body).compact_map(&.strip.match(ARRAY_KEY_RE).try(&.[1]))
      end
      [] of String
    end

    # Inside of an `array( … )` / `[ … ]` literal, or nil for anything else.
    private def php_array_body(expr : String) : String?
      s = expr.strip
      if m = s.match(/\Aarray\s*\((.*)\)\z/mi)
        m[1]
      elsif s.starts_with?('[') && s.ends_with?(']')
        s[1...-1]
      end
    end

    STRING_PROPERTY_RE = /\b(?:public|protected|private|var)\s+(?:static\s+)?(?:\??[\w\\]+\s+)?\$(\w+)\s*=\s*(?:'([^'\\]*)'|"([^"\\$]*)")/

    # `protected $namespace = 'myplugin/v2';`-style string properties of the
    # file's classes, for resolving `$this->namespace`. A property inherited
    # from a class in another file is not seen.
    private def string_properties(content : String) : Hash(String, String)
      properties = {} of String => String
      content.scan(STRING_PROPERTY_RE) { |m| properties[m[1]] ||= m[2]? || m[3] }
      properties
    end

    # The value of a string literal, `$this->prop`, or a `.` concatenation of
    # them; nil when any piece is something else.
    private def resolve_string_expr(arg : String, properties : Hash(String, String)) : String?
      String.build do |io|
        Noir::TopLevelSplit.split(arg, '.', SPLIT_ARGS_RULES).each do |piece|
          if literal = literal_arg(piece)
            io << literal
          elsif (prop = piece.strip.match(/\A\$this->(\w+)\z/)) && (value = properties[prop[1]]?)
            io << value
          else
            return
          end
        end
      end
    end

    # `/wp-json/` + namespace + route, collapsing duplicate slashes.
    private def build_rest_path(namespace : String, route : String) : String
      ns = namespace.strip.strip('/')
      rt = route.strip
      combined = "/wp-json/#{ns}/#{rt}"
      combined = combined.gsub(/\/+/, "/")
      combined = combined.chomp('/') if combined.size > 1
      normalize_wp_route(combined)
    end

    # Collect every HTTP verb referenced inside the `register_rest_route`
    # argument list: literal `'methods' => 'GET'` / `array('GET','POST')`
    # forms plus the `WP_REST_Server::READABLE`-style constants.
    private def extract_rest_methods(raw_args : String) : Array(String)
      methods = [] of String
      # Strip PHP comments so a commented-out `'methods' => 'DELETE'` (or a
      # `WP_REST_Server::EDITABLE` in a docblock) does not emit a phantom verb.
      args = strip_php_comments(raw_args)

      REST_METHOD_CONSTANTS.each do |constant, verbs|
        methods.concat(verbs) if args.includes?("WP_REST_Server::#{constant}")
      end

      # `'methods' => 'GET, POST'` / `"methods" => "GET"`.
      args.scan(/['"]methods['"]\s*=>\s*['"]([^'"]+)['"]/i) do |m|
        m[1].split(',').each do |verb|
          v = verb.strip.upcase
          methods << v if ALL_HTTP_VERBS.includes?(v)
        end
      end

      # `'methods' => array('GET','POST')` / `['GET','POST']`.
      args.scan(/['"]methods['"]\s*=>\s*(?:array\s*\(|\[)([^\)\]]*)/i) do |m|
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |verb|
          v = verb[1].strip.upcase
          methods << v if ALL_HTTP_VERBS.includes?(v)
        end
      end

      methods.uniq
    end

    # -- Admin AJAX / admin-post ----------------------------------------

    private def analyze_action_hooks(content : String, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))
      seen = Set(String).new

      # add_action('wp_ajax_foo', ...) / wp_ajax_nopriv_foo
      # add_action('admin_post_foo', ...) / admin_post_nopriv_foo
      #
      # The trailing `\s*,` requires the hook name to be a *complete* string
      # literal (followed by the callback argument). This rejects a
      # prefix+variable concatenation like `'wp_ajax_myplugin_' . $tab`,
      # whose closing quote is followed by `.` — otherwise we would emit the
      # truncated phantom action `myplugin_`.
      pattern = /add_action\s*\(\s*['"](wp_ajax_(?:nopriv_)?|admin_post_(?:nopriv_)?)([A-Za-z0-9_\-]+)['"]\s*,/i
      content.scan(pattern) do |match|
        hook_prefix = match[1].downcase
        action = match[2]
        next if action.empty?

        base_path = hook_prefix.starts_with?("wp_ajax_") ? ADMIN_AJAX_PATH : ADMIN_POST_PATH
        url = "#{base_path}?action=#{action}"

        DISPATCH_METHODS.each do |method|
          dedup_key = "#{method} #{url}"
          next if seen.includes?(dedup_key)
          seen.add(dedup_key)

          params = [Param.new("action", action, "query")]
          endpoints << Endpoint.new(url, method, params, details.dup)
        end
      end

      endpoints
    end

    # -- Helpers ---------------------------------------------------------

    # WordPress REST routes are PCRE fragments. Rewrite named capture
    # groups to `{name}` and strip the residual regex syntax that would
    # otherwise leak into the emitted URL:
    #   /books/(?P<id>\d+)          -> /books/{id}
    #   /(?P<type>(post|page))      -> /{type}       (balanced inner group)
    #   /thing(?:/(?P<id>\d+))?     -> /thing/{id}   (non-capturing + optional)
    private def normalize_wp_route(route : String) : String
      result = replace_named_groups(route)
      strip_wp_regex_artifacts(result)
    end

    # Replace `(?P<name>...)` / `(?<name>...)` with `{name}`, consuming the
    # *balanced* group body (which may itself contain nested `(...)`), so an
    # inner group does not truncate the match and leave a stray `)`.
    private def replace_named_groups(route : String) : String
      result = route
      loop do
        m = result.match(/\(\?P?<([A-Za-z_]\w*)>/)
        break unless m
        open_paren = m.begin(0)
        break unless open_paren
        close = matching_regex_paren(result, open_paren)
        break unless close
        result = result[0...open_paren] + "{#{m[1]}}" + result[(close + 1)..]
      end
      result
    end

    # Drop leftover PCRE syntax that is never part of a real URL path:
    # non-capturing groups, bare grouping parens, anchors, and quantifiers.
    # `{name}` placeholders are untouched (they contain none of these).
    private def strip_wp_regex_artifacts(route : String) : String
      r = route.gsub("(?:", "")
      r = r.gsub(/[()^$?]/, "")
      r = r.gsub(/\/+/, "/")
      r = r.chomp('/') if r.size > 1
      r
    end

    # Balance-match the `)` closing the `(` at `open`, honoring `\`-escapes
    # and `[...]` character classes (a `)` inside a class or after a
    # backslash is literal, not a group close). Scoped to regex fragments —
    # unlike find_matching_paren it does not treat `#`/`//` as comments.
    private def matching_regex_paren(s : String, open : Int32) : Int32?
      depth = 0
      in_class = false
      i = open
      while i < s.size
        c = s[i]
        if c == '\\'
          i += 2
          next
        elsif in_class
          in_class = false if c == ']'
        elsif c == '['
          in_class = true
        elsif c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end
      nil
    end

    # Remove `//`, `#`, and `/* */` PHP comments, preserving string
    # literals (so a `#` or `//` inside a quoted route is kept).
    private def strip_php_comments(code : String) : String
      out = String::Builder.new
      i = 0
      size = code.size
      in_string = false
      quote = '\0'
      escaped = false
      while i < size
        c = code[i]
        nxt = i + 1 < size ? code[i + 1] : '\0'
        if in_string
          out << c
          if escaped
            escaped = false
          elsif c == '\\'
            escaped = true
          elsif c == quote
            in_string = false
          end
          i += 1
        elsif c == '\'' || c == '"'
          in_string = true
          quote = c
          out << c
          i += 1
        elsif c == '/' && nxt == '/'
          i += 2
          while i < size && code[i] != '\n'
            i += 1
          end
        elsif c == '#'
          i += 1
          while i < size && code[i] != '\n'
            i += 1
          end
        elsif c == '/' && nxt == '*'
          i += 2
          while i < size && !(code[i] == '*' && (i + 1 < size ? code[i + 1] : '\0') == '/')
            i += 1
          end
          i += 2
        else
          out << c
          i += 1
        end
      end
      out.to_s
    end

    private def extract_wp_path_params(route : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new
      route.scan(/\{(\w+)\}/) do |m|
        name = m[1]
        next if seen.includes?(name)
        seen.add(name)
        params << Param.new(name, "", "path")
      end
      params
    end

    # A lone single/double-quoted string literal (the entire argument),
    # or nil if the argument is anything else (variable, call, concat,
    # array). Anchored so `$x . '/v1'` and `[...]` are rejected.
    private def literal_arg(arg : String) : String?
      s = arg.strip
      if m = s.match(/\A'((?:[^'\\]|\\.)*)'\z/)
        return m[1]
      end
      if m = s.match(/\A"((?:[^"\\]|\\.)*)"\z/)
        return m[1]
      end
      nil
    end

    # `Rules::SHARED_DEPTH_RAW` with a trailing empty dropped and, like
    # erlang/cowboy.cr, WITHOUT clamping: the body this replaces closed
    # brackets with a bare `depth -= 1`, so a fragment beginning with a
    # closer (`")x, y"`) drives depth negative and stops splitting. That is
    # observable on the regex-sliced input this actually receives, so it is
    # preserved rather than normalised.
    #
    # File-local because wordpress is the only splitter pairing
    # `clamp: false` with unstripped parts.
    SPLIT_ARGS_RULES = Noir::TopLevelSplit::Rules.new(
      nest: Noir::TopLevelSplit::Nest::Paren | Noir::TopLevelSplit::Nest::Bracket |
            Noir::TopLevelSplit::Nest::Brace,
      quotes: "\"'",
      escape: Noir::TopLevelSplit::Escape::InQuotes,
      strip: false,
      empties: Noir::TopLevelSplit::Empties::DropTrailing,
      per_kind: false,
      clamp: false,
    )

    # Split a PHP argument list on top-level commas, ignoring commas
    # nested inside (), [], {} or quoted strings. Only the first two
    # arguments are needed, but splitting fully keeps the logic simple.
    #
    # The empty-input guard is the old tail condition
    # `if start <= args.size - 1 || parts.empty?`, whose `|| parts.empty?`
    # arm fires for exactly one input: `""`, which yielded `[""]` and not
    # `[]`. `Empties::DropTrailing` can only return `[]` for that same
    # input, so restoring it here is exact — and cheaper than a fourth
    # `Empties` case for one caller.
    private def split_top_level_args(args : String) : Array(String)
      parts = Noir::TopLevelSplit.split(args, ',', SPLIT_ARGS_RULES)
      parts.empty? ? [""] : parts
    end

    # ASCII delimiters for the paren matcher below (mirrors PhpEngine's
    # brace matcher; all < 0x80 so UTF-8 multi-byte sequences are safe).
    private BYTE_NL     = '\n'.ord.to_u8
    private BYTE_STAR   = '*'.ord.to_u8
    private BYTE_SLASH  = '/'.ord.to_u8
    private BYTE_HASH   = '#'.ord.to_u8
    private BYTE_BSLASH = '\\'.ord.to_u8
    private BYTE_DQ     = '"'.ord.to_u8
    private BYTE_SQ     = '\''.ord.to_u8
    private BYTE_OPAREN = '('.ord.to_u8
    private BYTE_CPAREN = ')'.ord.to_u8

    # Find the `)` that closes the `(` at `open_pos`, skipping parens
    # inside strings and comments. Byte-scanned to stay linear on
    # multi-byte (e.g. CJK-commented) source.
    private def find_matching_paren(content : String, open_pos : Int32) : Int32?
      bytes = content.to_slice
      start = content.char_index_to_byte_index(open_pos)
      return unless start && start < bytes.size && bytes[start] == BYTE_OPAREN

      depth = 0
      in_string = false
      in_line_comment = false
      in_block_comment = false
      escaped = false
      quote = 0_u8
      pos = start
      size = bytes.size

      while pos < size
        char = bytes[pos]
        next_char = pos + 1 < size ? bytes[pos + 1] : 0_u8

        if in_line_comment
          in_line_comment = false if char == BYTE_NL
        elsif in_block_comment
          if char == BYTE_STAR && next_char == BYTE_SLASH
            in_block_comment = false
            pos += 1
          end
        elsif in_string
          if escaped
            escaped = false
          elsif char == BYTE_BSLASH
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == BYTE_SLASH && next_char == BYTE_SLASH
          in_line_comment = true
          pos += 1
        elsif char == BYTE_SLASH && next_char == BYTE_STAR
          in_block_comment = true
          pos += 1
        elsif char == BYTE_HASH
          in_line_comment = true
        elsif char == BYTE_DQ || char == BYTE_SQ
          in_string = true
          quote = char
        elsif char == BYTE_OPAREN
          depth += 1
        elsif char == BYTE_CPAREN
          depth -= 1
          return content.byte_index_to_char_index(pos) if depth == 0
        end

        pos += 1
      end

      nil
    end
  end
end
