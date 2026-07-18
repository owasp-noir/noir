require "../../engines/php_engine"

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

      endpoints.concat(analyze_rest_routes(content, path)) if content.includes?("register_rest_route")
      if content.includes?("wp_ajax_") || content.includes?("admin_post_")
        endpoints.concat(analyze_action_hooks(content, path))
      end

      endpoints
    end

    # -- REST API --------------------------------------------------------

    private def analyze_rest_routes(content : String, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      details = Details.new(PathInfo.new(path))

      offset = 0
      while call_start = content.index("register_rest_route", offset)
        paren_open = content.index('(', call_start)
        paren_close = paren_open ? find_matching_paren(content, paren_open) : nil

        if paren_open && paren_close
          # Advance past the whole balanced call for the next iteration.
          offset = paren_close + 1
          args = content[(paren_open + 1)...paren_close]

          namespace, route = namespace_and_route(args)
          # The namespace/route must be the first two *positional* args and
          # both must be plain string literals. A dynamic value ($this->
          # namespace, concatenation, a WP_REST_Controller subclass) can't be
          # resolved statically — skip rather than emit a bogus URL such as
          # /wp-json/books/{id}/GET (which is what naively scanning for the
          # first two literals anywhere in the arg list would produce).
          if namespace && route
            full_path = build_rest_path(namespace, route)
            methods = extract_rest_methods(args)
            methods = ["GET"] if methods.empty?
            params = extract_wp_path_params(full_path)

            methods.uniq.each do |method|
              endpoints << Endpoint.new(full_path, method, params.dup, details.dup)
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

    # Namespace + route are register_rest_route's first two positional
    # arguments. Return each only when that whole argument is a single
    # string literal; a variable/concatenation yields nil so the caller
    # skips the route instead of misreading a later literal as the route.
    private def namespace_and_route(args : String) : Tuple(String?, String?)
      parts = split_top_level_args(args)
      return {nil, nil} if parts.size < 2
      {literal_arg(parts[0]), literal_arg(parts[1])}
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

    # Split a PHP argument list on top-level commas, ignoring commas
    # nested inside (), [], {} or quoted strings. Only the first two
    # arguments are needed, but splitting fully keeps the logic simple.
    private def split_top_level_args(args : String) : Array(String)
      parts = [] of String
      depth = 0
      in_string = false
      quote = '\0'
      escaped = false
      start = 0
      args.each_char_with_index do |char, i|
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '\'', '"'
          in_string = true
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1
        when ','
          if depth == 0
            parts << args[start...i]
            start = i + 1
          end
        else
          # no-op
        end
      end
      parts << args[start..] if start <= args.size - 1 || parts.empty?
      parts
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
