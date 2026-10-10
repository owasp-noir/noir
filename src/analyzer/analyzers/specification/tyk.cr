require "../../engines/specification_engine"
require "../../../utils/url_path"

module Analyzer::Specification
  # Tyk classic API definitions: `proxy.listen_path` is the public prefix and
  # every `version_data.versions.*.extended_paths.<policy>[]` entry (and the
  # legacy `paths.<policy>` string lists) names a path under it, for the
  # `method_actions` / `method` verbs. The listen path itself is emitted for
  # any verb unless a `white_list` restricts the API to its listed paths.
  class Tyk < SpecificationEngine
    analyzer_for "tyk"

    # `"path": "/admin"` / `listen_path: /orders`, for the line an entry is on.
    PATH_LINE = /["']?(?:listen_)?path["']?\s*:\s*["']?([^"'\s,]+)/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::TYK_SPEC) do |path, details|
        content = read_file_content(path)
        lines = value_lines(content, PATH_LINE)
        if path.ends_with?(".json")
          definitions(parse_json_lenient(content)).each { |definition| process(definition, details, lines) }
        else
          parse_all_yaml_template(content).each do |doc|
            next unless doc.as_h?.try(&.[YAML::Any.new("kind")]?.try(&.as_s?)) == "ApiDefinition"
            # Same document shape as the classic JSON definition, under `spec`.
            if spec = doc[YAML::Any.new("spec")]?.try(&.as_h?)
              process(JSON.parse(spec.to_json), details, lines)
            end
          end
        end
      end

      @result
    end

    # A bare definition, the dashboard's `{"api_definition": {...}}`, or an
    # export's `{"apis": [{"api_definition": {...}}]}`.
    private def definitions(root : JSON::Any) : Array(JSON::Any)
      return [] of JSON::Any unless root_h = root.as_h?
      if apis = root_h["apis"]?.try(&.as_a?)
        apis.compact_map { |api| api.as_h?.try(&.["api_definition"]?) }
      elsif definition = root_h["api_definition"]?
        [definition]
      else
        [root]
      end
    end

    private def process(definition : JSON::Any, details : Details, lines : Hash(String, Array(Int32)))
      return unless definition_h = definition.as_h?
      return unless listen_path = definition_h["proxy"]?.try(&.as_h?).try(&.["listen_path"]?).try(&.as_s?).presence

      whitelisted = false
      definition_h["version_data"]?.try(&.as_h?).try(&.["versions"]?).try(&.as_h?).try(&.each_value do |version|
        next unless version_h = version.as_h?
        version_h["extended_paths"]?.try(&.as_h?).try(&.each do |policy, entries|
          entries.as_a?.try(&.each do |entry|
            # `cache` is a plain list of paths; every other policy lists objects.
            entry_h = entry.as_h?
            next unless sub_path = (entry_h ? entry_h["path"]?.try(&.as_s?) : entry.as_s?).presence
            methods = entry_h.try { |h| h["method_actions"]?.try(&.as_h?).try(&.keys) || json_strings(h["method"]?) } || [] of String
            whitelisted = true if policy == "white_list"
            emit(Noir::URLPath.join(listen_path, sub_path), methods, policy, details_at(details, take_line(lines, sub_path)))
          end)
        end)
        version_h["paths"]?.try(&.as_h?).try(&.each do |policy, entries|
          json_strings(entries).each do |sub_path|
            whitelisted = true if policy == "white_list"
            emit(Noir::URLPath.join(listen_path, sub_path), [] of String, policy, details_at(details, take_line(lines, sub_path)))
          end
        end)
      end)

      emit(listen_path, [] of String, nil, details_at(details, take_line(lines, listen_path))) unless whitelisted
    end

    private def emit(url : String, methods : Array(String), policy : String?, details : Details)
      methods = methods.map(&.upcase)
      methods = ["ANY"] if methods.empty?
      methods.each do |method|
        endpoint = Endpoint.new(url, method, details)
        endpoint.add_tag(Tag.new("tyk-policy", policy, "tyk_analyzer")) if policy
        @result << endpoint
      end
    end
  end
end
