require "../models/endpoint"
require "../utils/js_literal_scanner"
require "./js_route_extractor"
require "./js_http_route_extractor"

module Noir
  # Reads the handler exports of a file-routed serverless function module
  # (Cloudflare Pages Functions, Vercel Functions, Netlify Functions): which
  # names it exports, where each handler's parameter list and body are, the
  # inline `config` object, and the request params a handler body reads.
  #
  # The URL comes from the file's location, so this layer only deals with
  # the module's contents. Text-based on purpose: these modules are mostly
  # TypeScript, which the vendored JavaScript grammar does not parse.
  module JSServerlessFunctionExtractor
    extend self

    # A resolved handler: the export it came from, its raw parameter list,
    # its body (block contents or expression), the 1-based line of the
    # export, and the line the body starts on (for callee locations).
    record Handler, name : String, params : String, body : String, line : Int32, body_line : Int32

    IDENT_RE = /\A[A-Za-z_$][\w$]*\z/

    # `export const config = {...}` (optionally typed, `satisfies Config`).
    CONFIG_EXPORT_RE = /\bexport\s+(?:const|let|var)\s+config\b\s*(?::[^=]+)?=\s*\{/
    # `config: {...}` inside the default-exported object (Netlify's
    # "Fetchable module" form: `export default { fetch, config: {...} }`).
    CONFIG_PROPERTY_RE = /(?:^|[{,\s])['"]?config['"]?\s*:\s*\{/
    DEFAULT_OBJECT_RE  = /(?:^|[^\w$.])export\s+default\s*\{/m

    STRING_LITERAL_RE = /"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`([^`$]*)`/

    # Inferred-from-body method checks on the request:
    # `req.method === "POST"`, `case "PUT":` under `switch (req.method)`,
    # `["GET", "HEAD"].includes(req.method)`, `event.httpMethod !== "POST"`.
    METHOD_COMPARE_RE  = /\b[A-Za-z_$][\w$]*\s*\.\s*(?:method|httpMethod)\s*[!=]==?\s*['"]([A-Za-z]+)['"]|['"]([A-Za-z]+)['"]\s*[!=]==?\s*[A-Za-z_$][\w$]*\s*\.\s*(?:method|httpMethod)\b/
    METHOD_SWITCH_RE   = /switch\s*\(\s*[A-Za-z_$][\w$]*\s*\.\s*(?:method|httpMethod)\s*\)\s*\{/
    METHOD_INCLUDES_RE = /\[\s*([^\]]+)\]\s*\.\s*includes\s*\(\s*[A-Za-z_$][\w$]*\s*\.\s*(?:method|httpMethod)\s*\)/
    KNOWN_METHODS      = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}

    MAX_RESOLVE_DEPTH = 4

    # The handler a module exports under `name`: `export [async] function
    # name(...)`, `export const name = <fn>`, CommonJS `exports.name = <fn>`,
    # or `export { local as name }`. Nil when the module does not export it.
    def exported_handler(content : String, name : String) : Handler?
      escaped = Regex.escape(name)
      if m = content.match(/(?:^|[^\w$.])export\s+(?:async\s+)?function\s*\*?\s*#{escaped}\s*(?:<[^>(]*>)?\s*\(/m)
        return function_from_paren(content, m.end(0) - 1, name, line_of(content, m))
      end
      if m = content.match(/(?:^|[^\w$.])export\s+(?:const|let|var)\s+#{escaped}\b\s*(?::[^=]+)?=(?![=>])\s*/m)
        return value_handler(content, m.end(0), name, line_of(content, m), 0)
      end
      if m = content.match(/(?:^|[^\w$.])(?:module\s*\.\s*)?exports\s*\.\s*#{escaped}\s*=(?![=>])\s*/m)
        return value_handler(content, m.end(0), name, line_of(content, m), 0)
      end
      if local = export_clause_local(content, name)
        return local_handler(content, local, name, 0)
      end
      nil
    end

    # The module's default export (`export default ...` or CommonJS
    # `module.exports = ...`). A default-exported object resolves to its
    # `fetch` method, the Fetchable-module shape. Nil when there is none.
    def default_handler(content : String) : Handler?
      if m = content.match(/(?:^|[^\w$.])export\s+default\s+/m)
        return value_handler(content, m.end(0), "default", line_of(content, m), 0)
      end
      if m = content.match(/(?:^|[^\w$.])export\s*\{[^}]*\b([A-Za-z_$][\w$]*)\s+as\s+default\b[^}]*\}/m)
        return local_handler(content, m[1], "default", 0)
      end
      if m = content.match(/(?:^|[^\w$.])module\s*\.\s*exports\s*=(?![=>])\s*/m)
        return value_handler(content, m.end(0), "default", line_of(content, m), 0)
      end
      nil
    end

    # Text of the module's inline `config` object (between the braces), or
    # nil.
    def config_object(content : String) : String?
      if match = content.match(CONFIG_EXPORT_RE)
        return braced_contents(content, match.end(0) - 1)
      end
      # Only a `config` property of the default-exported object counts; the
      # same key on some other object literal is unrelated.
      default_export = content.match(DEFAULT_OBJECT_RE) || return
      object = braced_contents(content, default_export.end(0) - 1) || return
      property = object.match(CONFIG_PROPERTY_RE) || return
      braced_contents(object, property.end(0) - 1)
    end

    private def braced_contents(text : String, open : Int32) : String?
      close = JSLiteralScanner.find_matching_brace(text, open) || return
      text[(open + 1)...close]
    end

    # String values of `key` in a config object: `path: "/a"` or
    # `path: ["/a", "/b"]` (also quoted keys). Non-literal values are ignored.
    def config_strings(config : String, key : String) : Array(String)
      match = config.match(/(?:^|[{,\s])['"]?#{Regex.escape(key)}['"]?\s*:\s*/m)
      return [] of String unless match
      start = match.end(0)
      rest = config[start..]
      if rest.starts_with?('[')
        close = rest.index(']') || return [] of String
        string_literals(rest[1...close])
      else
        first = rest.match(/\A#{STRING_LITERAL_RE.source}/)
        first ? string_literals(first[0]) : [] of String
      end
    end

    def config_key?(config : String, key : String) : Bool
      config.matches?(/(?:^|[{,\s])['"]?#{Regex.escape(key)}['"]?\s*:/m)
    end

    # Methods a catch-all handler actually branches on. Empty when the body
    # does not check the request method.
    def inferred_methods(body : String) : Array(String)
      methods = [] of String
      body.scan(METHOD_COMPARE_RE) do |m|
        add_method(methods, m[1]? || m[2]?)
      end
      body.scan(METHOD_INCLUDES_RE) do |m|
        string_literals(m[1]).each { |verb| add_method(methods, verb) }
      end
      body.scan(METHOD_SWITCH_RE) do |m|
        open = m.end(0) - 1
        close = JSLiteralScanner.find_matching_brace(body, open) || next
        body[(open + 1)...close].scan(/\bcase\s+['"]([A-Za-z]+)['"]\s*:/) do |c|
          add_method(methods, c[1])
        end
      end
      methods
    end

    # Request params a handler reads. `style` picks how the first parameter
    # is interpreted:
    # - `:request` — it is the request (Vercel/Netlify `(req, ...)`), or
    #   destructures one.
    # - `:context` — it is an event context carrying `.request` and
    #   `.params` (Cloudflare Pages `(context)` / `({ request, params })`).
    # - `:lambda` — it is a Lambda-style event (Netlify v1 `(event)`):
    #   `queryStringParameters`, `headers`, a string `body`.
    def extract_request_params(handler : Handler, endpoint : Endpoint, style : Symbol) : Nil
      body = normalized_body(handler, style)
      return if body.empty?

      JSRouteExtractor.extract_header_params(body, endpoint)
      JSRouteExtractor.extract_cookie_params(body, endpoint)
      JSRouteExtractor.extract_query_params(body, endpoint)
      JSRouteExtractor.extract_body_params(body, endpoint)
      JSHttpRouteExtractor.extract_fetch_request_params(body, endpoint)
      extract_lambda_query_params(body, endpoint) if style == :lambda
    end

    # Rewrite every reference to the handler's request object as `req`, the
    # spelling the shared param extractors look for.
    private def normalized_body(handler : Handler, style : Symbol) : String
      body = handler.body
      first = handler.params.lstrip
      request_names = [] of String

      if first.starts_with?('{')
        close = JSLiteralScanner.find_matching_brace(first, 0) || return body
        destructured_bindings(first[1...close]).each do |key, local|
          request_names << local if key == "request" || (style != :context && key == "req")
        end
      elsif name = first_identifier(first)
        if style == :context
          body = body.gsub(/\b#{Regex.escape(name)}\s*\.\s*request\b/, "req")
          # `const { request } = context` / `const request = context.request`
          body.scan(/(?:const|let|var)\s*\{([^}]*)\}\s*=\s*#{Regex.escape(name)}\b/) do |m|
            destructured_bindings(m[1]).each do |key, local|
              request_names << local if key == "request"
            end
          end
        else
          request_names << name
        end
      end

      request_names.uniq.each do |request_name|
        next if request_name == "req"
        body = body.gsub(/(?<![\w$.])#{Regex.escape(request_name)}(?=\s*[.\[])/, "req")
      end
      body
    end

    private def extract_lambda_query_params(body : String, endpoint : Endpoint) : Nil
      body.scan(/\breq\s*\.\s*(?:multiValue)?queryStringParameters\s*\??\.\s*([A-Za-z_$][\w$]*)/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query"))
      end
      body.scan(/\breq\s*\.\s*(?:multiValue)?queryStringParameters\s*\??\.?\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query"))
      end
      body.scan(/(?:const|let|var)\s*\{([^}]*)\}\s*=\s*req\s*\.\s*(?:multiValue)?queryStringParameters\b/) do |m|
        destructured_bindings(m[1]).each do |key, _|
          endpoint.push_param(Param.new(key, "", "query"))
        end
      end
    end

    # `{ request, params: p, env = {} }` → [{"request", "request"},
    # {"params", "p"}, {"env", "env"}]. Nested patterns and rest elements
    # are skipped.
    private def destructured_bindings(inner : String) : Array(Tuple(String, String))
      bindings = [] of Tuple(String, String)
      inner.split(',').each do |raw|
        part = raw.split('=', 2).first.strip
        next if part.empty? || part.starts_with?("...")
        key, _, local = part.partition(':')
        key = key.strip.strip('"').strip('\'')
        local = local.strip
        local = key if local.empty?
        # A typed parameter list (`{ request }: EventContext`) leaves the
        # type after the brace, not here; anything else non-identifier is a
        # nested pattern.
        next unless key.matches?(IDENT_RE) && local.matches?(IDENT_RE)
        bindings << {key, local}
      end
      bindings
    end

    private def first_identifier(params : String) : String?
      if m = params.match(/\A\s*([A-Za-z_$][\w$]*)/)
        m[1]
      end
    end

    private def add_method(methods : Array(String), raw : String?) : Nil
      return unless raw
      verb = raw.upcase
      methods << verb if KNOWN_METHODS.includes?(verb) && !methods.includes?(verb)
    end

    private def string_literals(text : String) : Array(String)
      values = [] of String
      text.scan(STRING_LITERAL_RE) do |m|
        values << (m[1]? || m[2]? || m[3]? || "")
      end
      values
    end

    # Resolve the value assigned to an export into a handler.
    private def value_handler(content : String, pos : Int32, name : String, line : Int32, depth : Int32) : Handler?
      return if depth > MAX_RESOLVE_DEPTH
      pos = skip_space(content, pos)
      rest = content[pos, 256]? || ""

      if m = rest.match(/\A(?:async\s+)?function\b\s*\*?\s*(?:[A-Za-z_$][\w$]*)?\s*(?:<[^>(]*>)?\s*\(/)
        return function_from_paren(content, pos + m[0].size - 1, name, line)
      end
      if m = rest.match(/\A(?:async\s*)?(?:<[^>(]*>\s*)?\(/)
        paren = pos + m[0].size - 1
        if arrow = arrow_from_paren(content, paren, name, line)
          return arrow
        end
      end
      if m = rest.match(/\A(?:async\s+)?([A-Za-z_$][\w$]*)\s*=>\s*/)
        return arrow_body(content, pos + m[0].size, m[1], name, line)
      end
      if rest.starts_with?('{')
        return object_fetch_handler(content, pos, name, line, depth)
      end
      if rest.starts_with?('[')
        # Cloudflare middleware chains: `export const onRequest = [auth, handler]`.
        inner = (content[(pos + 1), 512]? || "").split(']', 2).first
        last = inner.split(',').map(&.strip).reject(&.empty?).last?
        if last && last.matches?(IDENT_RE)
          return local_handler(content, last, name, depth + 1) || Handler.new(name, "", "", line, line)
        end
        return Handler.new(name, "", "", line, line)
      end
      if m = rest.match(/\A([A-Za-z_$][\w$.]*)\s*\(/)
        # A wrapper call (`withAuth(handler)`, `schedule("@daily", fn)`):
        # use the first function argument or referenced local function.
        paren = pos + m[0].size - 1
        close = JSLiteralScanner.find_matching_paren(content, paren) || return Handler.new(name, "", "", line, line)
        args = content[(paren + 1)...close]
        if inner = first_function_in(content, paren + 1, close, name, line)
          return inner
        end
        args.split(',').map(&.strip).reverse_each do |arg|
          next unless arg.matches?(IDENT_RE)
          if resolved = local_handler(content, arg, name, depth + 1)
            return resolved
          end
        end
        return Handler.new(name, "", args, line, line)
      end
      if m = rest.match(/\A([A-Za-z_$][\w$]*)\s*(?:;|\n|\z)/)
        return local_handler(content, m[1], name, depth + 1) || Handler.new(name, "", "", line, line)
      end
      nil
    end

    # A non-exported local the export points at: `function local(...)` or
    # `const local = <fn>`.
    private def local_handler(content : String, local : String, name : String, depth : Int32) : Handler?
      return if depth > MAX_RESOLVE_DEPTH
      escaped = Regex.escape(local)
      if m = content.match(/(?:^|[^\w$.])(?:async\s+)?function\s*\*?\s*#{escaped}\s*(?:<[^>(]*>)?\s*\(/m)
        return function_from_paren(content, m.end(0) - 1, name, line_of(content, m))
      end
      if m = content.match(/(?:^|[^\w$.])(?:const|let|var)\s+#{escaped}\b\s*(?::[^=]+)?=(?![=>])\s*/m)
        return value_handler(content, m.end(0), name, line_of(content, m), depth + 1)
      end
      nil
    end

    # `export default { async fetch(req, ctx) {...} }` / `{ fetch: handler }`.
    private def object_fetch_handler(content : String, open : Int32, name : String, line : Int32, depth : Int32) : Handler?
      close = JSLiteralScanner.find_matching_brace(content, open) || return
      object = content[open..close]
      if m = object.match(/(?:^|[{,\s])(?:async\s+)?fetch\s*\(/m)
        return function_from_paren(content, open + m.end(0) - 1, name, line)
      end
      if m = object.match(/(?:^|[{,\s])fetch\s*:\s*/m)
        return value_handler(content, open + m.end(0), name, line, depth + 1)
      end
      nil
    end

    private def first_function_in(content : String, from : Int32, to : Int32, name : String, line : Int32) : Handler?
      segment = content[from...to]
      if m = segment.match(/(?:^|[^\w$.])(?:async\s+)?function\b\s*\*?\s*(?:[A-Za-z_$][\w$]*)?\s*\(/m)
        return function_from_paren(content, from + m.end(0) - 1, name, line)
      end
      # Probe each `(` on an ASCII stand-in (one char per char, so indices
      # carry over): the char-indexed scanner copies a non-ASCII string into
      # a char array on every call, and this loop calls it once per paren.
      probe = segment.bytesize == segment.size ? segment : segment.gsub(/[^\x00-\x7F]/, '_')
      offset = 0
      while idx = probe.index('(', offset)
        close = JSLiteralScanner.find_matching_paren(probe, idx)
        if close && probe[(close + 1), 200]?.try(&.matches?(ARROW_AFTER_PARAMS))
          return arrow_from_paren(content, from + idx, name, line)
        end
        offset = idx + 1
      end
      if m = segment.match(/(?:^|[^\w$.])(?:async\s+)?([A-Za-z_$][\w$]*)\s*=>\s*/m)
        return arrow_body(content, from + m.end(0), m[1], name, line)
      end
      nil
    end

    private def function_from_paren(content : String, paren : Int32, name : String, line : Int32) : Handler?
      close = JSLiteralScanner.find_matching_paren(content, paren) || return
      params = content[(paren + 1)...close]
      open = content.index('{', close) || return Handler.new(name, params, "", line, line)
      body_close = JSLiteralScanner.find_matching_brace(content, open) || return Handler.new(name, params, "", line, line)
      Handler.new(name, params, content[(open + 1)...body_close], line, line_at(content, open))
    end

    # What follows an arrow's `(params)`: an optional return type, then `=>`.
    ARROW_AFTER_PARAMS = /\A\s*(?::\s*[^=;{}]+?)?\s*=>\s*/

    # `(params) [: Type] => body` starting at the `(`; nil when the paren is
    # not an arrow's parameter list.
    private def arrow_from_paren(content : String, paren : Int32, name : String, line : Int32) : Handler?
      close = JSLiteralScanner.find_matching_paren(content, paren) || return
      after = content[(close + 1), 200]? || ""
      arrow = after.match(ARROW_AFTER_PARAMS) || return
      arrow_body(content, close + 1 + arrow[0].size, content[(paren + 1)...close], name, line)
    end

    private def arrow_body(content : String, pos : Int32, params : String, name : String, line : Int32) : Handler
      body_line = line_at(content, pos)
      if content[pos]? == '{'
        close = JSLiteralScanner.find_matching_brace(content, pos)
        return Handler.new(name, params, close ? content[(pos + 1)...close] : "", line, body_line)
      end
      # Expression body: up to the next top-level statement.
      stop = content.index(/\n(?=\S)/, pos) || content.size
      Handler.new(name, params, content[pos...stop], line, body_line)
    end

    private def export_clause_local(content : String, name : String) : String?
      content.scan(/(?:^|[^\w$.])export\s*\{([^}]*)\}(?!\s*from\b)/m) do |m|
        m[1].split(',').each do |part|
          pieces = part.strip.split(/\s+as\s+/)
          case pieces.size
          when 1
            return pieces[0] if pieces[0] == name
          when 2
            return pieces[0].strip if pieces[1].strip == name
          end
        end
      end
      nil
    end

    private def skip_space(content : String, pos : Int32) : Int32
      while (char = content[pos]?) && char.whitespace?
        pos += 1
      end
      pos
    end

    private def line_of(content : String, match : Regex::MatchData) : Int32
      start = match.begin(0) || 0
      # Skip the boundary char the patterns consume before `export`.
      while (char = content[start]?) && !char.letter?
        start += 1
      end
      line_at(content, start)
    end

    private def line_at(content : String, index : Int32) : Int32
      content[0, index].count('\n') + 1
    end
  end
end
