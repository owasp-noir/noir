require "../../miniparsers/js_serverless_function_extractor"
require "../../miniparsers/js_callee_extractor"
require "../../utils/serverless_layout"

module Analyzer::Javascript
  # Shared by the file-routed serverless adapters (Cloudflare Pages
  # Functions, Vercel Functions, Netlify Functions). A mixin for
  # `JavascriptEngine` subclasses: each platform decides the URL and the
  # handler exports; this turns a resolved handler into an endpoint.
  module ServerlessFunctionSupport
    # The verb for a handler that serves every method and doesn't branch on
    # the request method — the same synthetic verb Firebase `onRequest`
    # functions and the Netlify/Vercel config analyzers use.
    ANY_METHOD = "ANY"

    # Endpoint for one handler: path params from the URL (`{id}` from a file
    # segment, `:id` from a Netlify URLPattern), the request params the
    # handler body reads, and its callees.
    protected def serverless_endpoint(url : String, verb : String, path : String,
                                      handler : Noir::JSServerlessFunctionExtractor::Handler?,
                                      style : Symbol, include_callee : Bool,
                                      path_params_in_query : Bool = false) : Endpoint
      endpoint = file_route_endpoint(url, verb, path, handler.try(&.line) || 1)
      url.scan(/(?:^|\/):([A-Za-z_]\w*)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      return endpoint unless handler

      Noir::JSServerlessFunctionExtractor.extract_request_params(handler, endpoint, style)
      # Vercel merges dynamic segments into `req.query`, so `req.query.id`
      # in `api/users/[id].ts` is the path param, not a second input.
      if path_params_in_query
        path_names = endpoint.params.select(&.param_type.==("path")).map(&.name)
        endpoint.params.reject! { |param| param.param_type == "query" && path_names.includes?(param.name) }
      end
      if include_callee && !handler.body.empty?
        callees = Noir::JSCalleeExtractor.callees_for_function_body(handler.body, path, handler.body_line,
          language: javascript_source_language(path))
        attach_js_callees(endpoint, callees)
      end
      endpoint
    end

    # Methods a catch-all handler serves: the ones its body branches on
    # (`req.method === "POST"`), otherwise every method.
    protected def catch_all_methods(handler : Noir::JSServerlessFunctionExtractor::Handler?) : Array(String)
      inferred = handler ? Noir::JSServerlessFunctionExtractor.inferred_methods(handler.body) : [] of String
      inferred.empty? ? [ANY_METHOD] : inferred
    end
  end
end
