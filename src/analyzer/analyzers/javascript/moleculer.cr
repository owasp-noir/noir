require "../../engines/javascript_engine"
require "../../../miniparsers/js_object_config_extractor"

module Analyzer::Javascript
  # Moleculer services reach HTTP only through a `moleculer-web` gateway
  # (`mixins: [ApiGateway]`), whose `settings.routes[]` map URLs to actions:
  #
  #   aliases: { "GET users/:id": "users.get" }  → GET /<route.path>/users/:id
  #   aliases: { "health": "api.health" }        → ANY
  #   aliases: { "REST posts": "posts" }         → the six CRUD routes
  #   autoAliases: true                          → every action's `rest:`
  #
  # Alias targets are resolved against the services' `actions` so the
  # action's `params` validator names the request params.
  class Moleculer < JavascriptEngine
    analyzer_for "js_moleculer"

    alias Config = Noir::JSObjectConfigExtractor::ConfigValue
    alias ConfigHash = Hash(String, Noir::JSObjectConfigExtractor::ConfigValue)

    PACKAGE_MARKERS = ["\"moleculer\":", "\"moleculer-web\":"]
    SERVICE_HINT    = /\b(?:actions|routes)\s*:/
    GATEWAY_IMPORT  = /(?:\bfrom\s*|\brequire\s*\(\s*)['"]moleculer-web['"]/
    # moleculer-web's `REST` alias shorthand.
    REST_ROUTES = [{"GET", "", "list"}, {"GET", "/:id", "get"}, {"POST", "", "create"},
                   {"PUT", "/:id", "update"}, {"PATCH", "/:id", "patch"}, {"DELETE", "/:id", "remove"}]

    record Service, path : String, schema : Noir::JSObjectConfigExtractor::ConfigObject, gateway : Bool
    record Action, path : String, line : Int32, params : Array(String)

    def analyze
      owners = js_package_owners(PACKAGE_MARKERS)
      return @result unless owners.values.includes?(true)

      services = ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
        content = read_file_content(path)
        next unless content.matches?(SERVICE_HINT) && owned_by_js_package?(path, owners)
        # The gateway mixin is what serves `settings.routes`; a look-alike
        # object elsewhere is not routed.
        gateway = content.matches?(GATEWAY_IMPORT)
        Noir::JSObjectConfigExtractor.extract(content, ["name"]).map { |schema| Service.new(path, schema, gateway) }
      end.flatten

      actions = {} of String => Action
      services.each do |service|
        name = full_name(service.schema) || next
        service.schema.hash("actions").try &.each do |action, definition|
          params = definition.as?(ConfigHash).try(&.["params"]?).as?(ConfigHash).try(&.keys.reject(&.starts_with?("$$"))) || [] of String
          actions["#{name}.#{action}"] = Action.new(service.path, service.schema.line, params)
        end
      end

      services.each do |service|
        next unless service.gateway
        settings = service.schema.hash("settings") || next
        global = settings["path"]?.as?(String) || ""
        settings["routes"]?.as?(Array).try &.each do |route|
          route = route.as?(ConfigHash) || next
          prefix = Noir::URLPath.absolute_join(global, route["path"]?.as?(String) || "")
          route["aliases"]?.as?(ConfigHash).try &.each do |key, target|
            alias_endpoints(service, prefix, key, target, actions)
          end
          auto_aliases(prefix, services, actions) if route["autoAliases"]? == true
        end
      end
      @result
    end

    private def alias_endpoints(gateway : Service, prefix : String, key : String, target : Config, actions : Hash(String, Action))
      parts = key.strip.split(/\s+/, 2)
      method, path = parts.size == 2 ? {parts[0].upcase, parts[1]} : {"*", parts[0]}
      action = case target
               when String then target
               when Array  then target.last?.as?(String) # middlewares, then the action
               when Hash   then target["action"]?.as?(String)
               end

      if method == "REST"
        return unless action
        REST_ROUTES.each do |verb, suffix, name|
          emit(gateway.path, gateway.schema.line, Noir::URLPath.absolute_join(prefix, path) + suffix, verb, actions["#{action}.#{name}"]?)
        end
      else
        emit(gateway.path, gateway.schema.line, Noir::URLPath.absolute_join(prefix, path), method, action.try { |name| actions[name]? })
      end
    end

    # `actions.<name>.rest`: `"GET /path"`, `"/path"`, `{ method, path, basePath }`,
    # or an array of those, under each of the service's `settings.rest`
    # base paths or its dotted full name. Like moleculer-web's
    # `regenerateAutoAliases`, any other `rest` value (`true`) and a
    # non-published action add nothing.
    private def auto_aliases(prefix : String, services : Array(Service), actions : Hash(String, Action))
      services.each do |service|
        name = full_name(service.schema) || next
        bases = case rest_base = service.schema.hash("settings").try(&.["rest"]?)
                when String then [rest_base]
                when Array  then rest_base.compact_map(&.as?(String))
                else             [name.gsub('.', '/')]
                end
        service.schema.hash("actions").try &.each do |action_name, definition|
          definition = definition.as?(ConfigHash) || next
          visibility = definition["visibility"]?
          next unless visibility.nil? || visibility == "published"
          rest = definition["rest"]?
          bases.each do |base|
            (rest.is_a?(Array) ? rest : [rest]).each do |entry|
              root = base
              case entry
              when String
                parts = entry.strip.split(/\s+/, 2)
                method, path = parts.size == 2 ? {parts[0].upcase, parts[1]} : {"*", parts[0]}
              when Hash
                method = entry["method"]?.as?(String).try(&.upcase) || "*"
                path = entry["path"]?.as?(String) || action_name
                root = entry["basePath"]?.as?(String) || base
              else next
              end
              emit(service.path, service.schema.line, Noir::URLPath.absolute_join(prefix, root, path), method, actions["#{name}.#{action_name}"]?)
            end
          end
        end
      end
    end

    private def emit(path : String, line : Int32, url : String, method : String, action : Action?)
      method = "ANY" if SYNTHETIC_ANY_METHODS.includes?(method)
      return unless method == "ANY" || ALLOWED_HTTP_METHODS.includes?(method)

      details = Details.new(PathInfo.new(path, line))
      details.add_path(PathInfo.new(action.path, action.line)) if action && action.path != path
      endpoint = Endpoint.new(url, method, details)
      if action
        # moleculer-web merges query, body and path params into `ctx.params`.
        type = method.in?("GET", "HEAD", "ANY") ? "query" : "json"
        # Whole names: `:idx` in the path must not swallow param `id`.
        path_params = url.scan(/:(\w+)/).map(&.[1])
        action.params.each do |param|
          endpoint.push_param(Param.new(param, "", type)) unless path_params.includes?(param)
        end
      end
      @result << endpoint
    end

    # `version: 2` → `v2.users`; a string version is used as-is.
    private def full_name(schema : Noir::JSObjectConfigExtractor::ConfigObject) : String?
      name = schema.string("name") || return
      case version = schema["version"]
      when Float64 then "v#{version.to_i}.#{name}"
      when String  then "#{version}.#{name}"
      else              name
      end
    end
  end
end
