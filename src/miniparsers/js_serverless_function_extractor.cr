require "../models/endpoint"
require "../utils/js_literal_scanner"
require "./js_route_extractor"
require "./js_http_route_extractor"
require "./js_handler_table"

module Noir
  # Reads the handler exports of a file-routed serverless function module
  # (Cloudflare Pages Functions, Vercel Functions, Netlify Functions): which
  # names it exports, where each handler's parameter list and body are, the
  # inline `config` object, and the request params a handler body reads.
  #
  # The URL comes from the file's location, so this layer only deals with
  # the module's contents. Discovery and body ranges come from the syntax
  # tree (`Noir::JSHandlerTable`); the request params are then read off the
  # body text.
  module JSServerlessFunctionExtractor
    extend self

    # A resolved handler: the export it came from, its raw parameter list,
    # its body (block contents or expression), the 1-based line of the
    # export, the line the body starts on, and (when asked for) its callees.
    record Handler, name : String, params : String, body : String, line : Int32, body_line : Int32,
      callees : Array(JSCalleeExtractor::Entry), methods : Array(String)

    IDENT_RE = /\A[A-Za-z_$][\w$]*\z/

    KNOWN_METHODS = JSHandlerTable::KNOWN_METHODS

    # The handler a module exports under `name`: `export [async] function
    # name(...)`, `export const name = <fn>`, CommonJS `exports.name = <fn>`,
    # or `export { local as name }`. Nil when the module does not export it.
    # `callees` also reads the handler's callees.
    def exported_handler(content : String, path : String, name : String, callees : Bool = false) : Handler?
      JSHandlerTable.for(content, path, callees).exports[name]?.try { |fn| handler(name, fn) }
    end

    # The module's default export (`export default ...` or CommonJS
    # `module.exports = ...`). A default-exported object resolves to its
    # `fetch` method, the Fetchable-module shape. Nil when there is none.
    def default_handler(content : String, path : String, callees : Bool = false) : Handler?
      JSHandlerTable.for(content, path, callees).default.try { |fn| handler("default", fn) }
    end

    private def handler(name : String, fn : JSHandlerTable::Fn) : Handler
      Handler.new(name, fn.params, fn.body, fn.line, fn.body_line, fn.callees, fn.methods)
    end

    alias Config = Hash(String, Array(String))

    # The module's inline `config` object as string values by key, or nil:
    # `export const config = {...}` (optionally typed or `satisfies`), or the
    # `config` property of the default-exported object.
    def config_object(content : String, path : String) : Config?
      JSHandlerTable.for(content, path).config
    end

    # String values of `key` in a config object: `path: "/a"` or
    # `path: ["/a", "/b"]` (also quoted keys). Non-literal values are ignored.
    def config_strings(config : Config, key : String) : Array(String)
      config[key]? || [] of String
    end

    def config_key?(config : Config, key : String) : Bool
      config.has_key?(key)
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
  end
end
