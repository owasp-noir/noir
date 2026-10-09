require "../../engines/specification_engine"
require "../../../utils/http_symbols"

module Analyzer::Specification
  # Parses Hoppscotch collection exports.
  #
  # A collection is `{v, name, folders[], requests[], auth?, headers?}`;
  # folders nest the same shape. A request carries `method`, `endpoint`,
  # `params`, `headers`, `body` and `auth`. `<<var>>` placeholders resolve
  # from Hoppscotch environment exports registered by the same detector
  # (`{name, variables: [{key, value|initialValue|currentValue, secret}]}`);
  # an unresolved one in the path becomes a `:var` path parameter, and one in
  # the host position is dropped as a base URL.
  class Hoppscotch < SpecificationEngine
    analyzer_for "hoppscotch"

    # Matched after `<<var>>` has been rewritten to `{{var}}`, so the shared
    # URL helpers recognise a templated host.
    TEMPLATE_VAR = /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/
    HOPP_VAR     = /<<\s*([A-Za-z0-9_.-]+)\s*>>/

    AUTH_HEADER_TYPES = {"basic", "bearer", "oauth-2", "digest", "hawk", "jwt", "aws-signature", "akamai-eg"}

    def analyze
      collections = [] of Tuple(JSON::Any, String)
      env = {} of String => String

      each_spec_file(Noir::LocatorKeys::HOPPSCOTCH_JSON, sorted: true) do |path|
        doc = parse_json_lenient(read_file_content(path))
        (doc.as_a? || [doc]).each do |node|
          # Environment exports and (newer) collection-level variables.
          node["variables"]?.try(&.as_a?).try { |variables| collect_env(variables, env) }
          collections << {node, path} if node["requests"]?
        end
      end

      collections.each do |node, path|
        walk(node, env, path, nil, [] of Param)
      end

      @result
    end

    # First file wins per key — environments are read in sorted path order.
    private def collect_env(variables : Array(JSON::Any), env : Hash(String, String))
      variables.each do |var|
        next unless key = var["key"]?.try(&.as_s?)
        value = var["value"]?.try(&.as_s?) || var["currentValue"]?.try(&.as_s?).presence || var["initialValue"]?.try(&.as_s?)
        env[key] = value if value && !env.has_key?(key)
      end
    end

    # A folder's `auth: {authType: "inherit"}` keeps the parent's, and its
    # `headers` add to the parent's.
    private def walk(node : JSON::Any, env : Hash(String, String), path : String, inherited_auth : JSON::Any?, inherited_headers : Array(Param))
      auth = own_auth(node["auth"]?) || inherited_auth
      headers = inherited_headers + key_value_params(node["headers"]?, env, "header")

      node["requests"]?.try(&.as_a?).try &.each do |request|
        process_request(request, env, path, auth, headers)
      rescue e
        @logger.debug "Exception processing Hoppscotch request"
        @logger.debug_sub e
      end

      node["folders"]?.try(&.as_a?).try &.each do |folder|
        walk(folder, env, path, auth, headers)
      end
    end

    private def process_request(request : JSON::Any, env : Hash(String, String), path : String, inherited_auth : JSON::Any?, inherited_headers : Array(Param))
      method = (request["method"]?.try(&.as_s?) || "GET").upcase
      return unless ALLOWED_HTTP_METHODS.includes?(method)
      return unless endpoint = request["endpoint"]?.try(&.as_s?)

      url = resolve(endpoint, env)
      url_path = template_url_path(url, TEMPLATE_VAR)
      return if url_path.empty?

      params = [] of Param
      request_query_pairs(url).each { |name, value| push_param_once(params, Param.new(name, value, "query")) }
      key_value_params(request["params"]?, env, "query").each { |param| push_param_once(params, param) }
      request_path_vars(url_path).each { |name| push_param_once(params, Param.new(name, "", "path")) }
      key_value_params(request["headers"]?, env, "header").each { |param| push_param_once(params, param) }
      inherited_headers.each { |param| push_param_once(params, param) }
      apply_auth(own_auth(request["auth"]?) || inherited_auth, env, params)
      body_params(request["body"]?, env).each { |param| push_param_once(params, param) }

      @result << Endpoint.new(url_path, method, params, Details.new(PathInfo.new(path)))
    end

    # Nil for an absent, inactive or `inherit` auth block, so the caller
    # falls back to the parent's.
    private def own_auth(auth : JSON::Any?) : JSON::Any?
      return unless auth && auth.as_h?
      return if auth["authActive"]?.try(&.as_bool?) == false
      return if auth["authType"]?.try(&.as_s?) == "inherit"
      auth
    end

    private def apply_auth(auth : JSON::Any?, env : Hash(String, String), params : Array(Param))
      return unless auth
      type = auth["authType"]?.try(&.as_s?) || ""
      if type == "api-key"
        return unless key = auth["key"]?.try(&.as_s?).presence
        param_type = auth["addTo"]?.try(&.as_s?) == "QUERY_PARAMS" ? "query" : "header"
        push_param_once(params, Param.new(resolve(key, env), resolve(auth["value"]?.try(&.as_s?) || "", env), param_type))
      elsif AUTH_HEADER_TYPES.includes?(type)
        push_param_once(params, Param.new("Authorization", "", "header"))
      end
    end

    private def body_params(body : JSON::Any?, env : Hash(String, String)) : Array(Param)
      params = [] of Param
      return params unless body && body.as_h?
      content_type = body["contentType"]?.try(&.as_s?) || ""
      raw = body["body"]?

      if content_type.includes?("json")
        if text = raw.try(&.as_s?)
          json_body_pairs(resolve(text, env), TEMPLATE_VAR).each { |name, value| params << Param.new(name, value, "json") }
        end
      elsif content_type.includes?("x-www-form-urlencoded")
        # Stored as Hoppscotch's raw key-value text: `key: value` per line,
        # `#` marking a disabled pair.
        raw.try(&.as_s?).try &.each_line do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.starts_with?('#')
          name, _, value = stripped.partition(':')
          params << Param.new(name.strip, value.strip, "form") unless name.strip.empty?
        end
      elsif content_type.includes?("multipart/form-data")
        params.concat(key_value_params(raw, env, "form"))
      end
      params
    end

    # Active `{key, value}` entries of a params/headers/form list.
    private def key_value_params(list : JSON::Any?, env : Hash(String, String), param_type : String) : Array(Param)
      params = [] of Param
      list.try(&.as_a?).try &.each do |entry|
        next unless name = entry["key"]?.try(&.as_s?).presence
        next if entry["active"]?.try(&.as_bool?) == false
        next if param_type == "header" && skipped_request_header?(name)
        params << Param.new(name, resolve(entry["value"]?.try(&.as_s?) || "", env), param_type)
      end
      params
    end

    # `<<var>>` from the environment, else rewritten to `{{var}}`.
    private def resolve(input : String, env : Hash(String, String)) : String
      return input unless input.includes?("<<")
      input.gsub(HOPP_VAR) { env.fetch($1, "{{#{$1}}}") }
    end
  end
end
