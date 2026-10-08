require "../../engines/javascript_engine"
require "../../../miniparsers/encore_extractor"

module Analyzer::Typescript
  # Encore.ts (https://encore.dev/docs/ts/primitives/defining-apis):
  #
  #   export const get = api(
  #     { expose: true, method: "GET", path: "/hello/:name" },
  #     async ({ name }: { name: string }): Promise<Response> => { ... },
  #   );
  #
  # No `path` means `/<service>.<export>`, the service being the nearest
  # `encore.service.ts` (`new Service("name")`); no `method` means POST.
  # Streams are WebSocket GETs; `api.static` serves files over GET.
  class Encore < Analyzer::Javascript::JavascriptEngine
    analyzer_for "ts_encore"

    TAGGER        = "encore_analyzer"
    QUERY_METHODS = %w[GET HEAD DELETE]
    IMPORT_RE     = /from\s*['"]encore\.dev\/api['"]/
    SERVICE_RE    = /new\s+Service\s*\(\s*['"]([^'"]+)['"]/
    NAMED_TYPE_RE = /\A(Header|Query|Cookie)\s*<\s*(?:['"]([^'"]+)['"])?/

    def analyze
      files = get_files_by_extensions(DEFAULT_EXTENSIONS)
      services = Hash(String, String).new
      files.each do |path|
        next unless File.basename(path).starts_with?("encore.service.")
        read_file_content(path).match(SERVICE_RE).try { |m| services[File.dirname(path)] = m[1] }
      end

      ordered_scan_files(files) do |path|
        content = read_file_content(path)
        next unless content.matches?(IMPORT_RE)
        next if Noir::JSRouteExtractor.test_stub_only?(path, content)
        Noir::EncoreExtractor.extract_ts(content).flat_map { |api| endpoints_for(api, path, service_for(path, services)) }
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end

    private def service_for(path : String, services : Hash(String, String)) : String
      dir = File.dirname(path)
      loop do
        return services[dir] if services.has_key?(dir)
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      File.basename(File.dirname(path))
    end

    private def endpoints_for(api : Noir::EncoreExtractor::TsApi, path : String, service : String) : Array(Endpoint)
      config = ->(key : String) { Noir::EncoreExtractor.ts_config_value(api.config, key) }
      url, path_names = Noir::EncoreExtractor.route(config.call("path").try { |v| Noir::EncoreExtractor.ts_strings(v).first? } || "/#{service}.#{api.name}")

      declared = config.call("method").try { |v| Noir::EncoreExtractor.ts_strings(v) } || [] of String
      methods = if api.kind == "static" || api.kind.starts_with?("stream")
                  ["GET"]
                elsif declared.empty?
                  ["POST"]
                else
                  declared.map { |m| m == "*" ? "ANY" : m.upcase }
                end
      expose = config.call("expose") == "true"
      auth = config.call("auth") == "true"

      methods.map do |method|
        endpoint = Endpoint.new(url, method, Details.new(PathInfo.new(path, api.line)))
        endpoint.protocol = "ws" if api.kind.starts_with?("stream")
        path_names.each { |name| endpoint.push_param(Param.new(name, "", "path")) }
        api.fields.each do |field|
          next if path_names.includes?(field.name)
          endpoint.push_param(param_for(field, method))
        end
        endpoint.add_tag(Tag.new("encore-access", expose ? "public" : "private", TAGGER))
        endpoint.add_tag(Tag.new("auth", "Encore auth endpoint", TAGGER)) if auth
        endpoint
      end
    end

    # `Header<"X-Name">`, `Query<T>` and `Cookie<"name">` place a field;
    # otherwise GET/HEAD/DELETE send it as a query param, the rest as JSON.
    private def param_for(field : Noir::EncoreExtractor::TsField, method : String) : Param
      if m = field.type.match(NAMED_TYPE_RE)
        Param.new(m[2]? || field.name, "", m[1].downcase)
      elsif QUERY_METHODS.includes?(method)
        Param.new(field.name, "", "query")
      else
        Param.new(field.name, "", "json")
      end
    end
  end
end
