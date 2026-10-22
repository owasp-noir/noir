require "../../engines/specification_engine"
require "../../../utils/http_symbols"

module Analyzer::Specification
  # Parses Thunder Client (VS Code extension) collections saved under
  # `thunder-tests/`: the legacy `thunderclient.json` (a flat array of
  # requests) and the newer `collections/*.json` (a collection object with a
  # `requests` array). A request carries `method`, `url`, `params`
  # (`isPath` marks a path variable), `headers`, `body` and `auth`.
  # `{{var}}` placeholders come from Thunder environments; an unresolved one
  # in the host position is dropped and one in the path becomes `:var`.
  class ThunderClient < SpecificationEngine
    analyzer_for "thunder_client"

    def analyze
      each_spec_file(Noir::LocatorKeys::THUNDER_CLIENT_JSON) do |path|
        doc = parse_json_lenient(read_file_content(path))
        requests(doc).each do |request|
          process_request(request, path)
        rescue e
          @logger.debug "Exception processing Thunder Client request"
          @logger.debug_sub e
        end
      end

      @result
    end

    # The request objects of a Thunder Client file: the top-level array, or
    # the `requests` of each collection object.
    private def requests(doc : JSON::Any) : Array(JSON::Any)
      nodes = doc.as_a? || [doc]
      nodes.flat_map do |node|
        next [] of JSON::Any unless node.as_h?
        if requests = node["requests"]?.try(&.as_a?)
          requests.select { |r| request?(r) }
        elsif request?(node)
          [node]
        else
          [] of JSON::Any
        end
      end
    end

    private def request?(node : JSON::Any) : Bool
      !!(node.as_h? && node["_id"]? && node["url"]?.try(&.as_s?) && node["method"]?.try(&.as_s?))
    end

    private def process_request(request : JSON::Any, path : String)
      method = request["method"].as_s.upcase
      return unless ALLOWED_HTTP_METHODS.includes?(method)
      url = request["url"].as_s
      url_path = template_url_path(url, MUSTACHE_VAR)
      return if url_path.empty?

      params = [] of Param
      request_query_pairs(url).each { |name, value| push_param_once(params, Param.new(name, value, "query")) }
      each_entry(request["params"]?) do |name, value, entry|
        push_param_once(params, Param.new(name, value, entry["isPath"]?.try(&.as_bool?) ? "path" : "query"))
      end
      request_path_vars(url_path).each { |name| push_param_once(params, Param.new(name, "", "path")) }
      each_entry(request["headers"]?) do |name, value|
        push_param_once(params, Param.new(name, value, "header")) unless skipped_request_header?(name)
      end

      auth_type = request["auth"]?.try(&.as_h?).try(&.["type"]?).try(&.as_s?) || "none"
      push_param_once(params, Param.new("Authorization", "", "header")) unless auth_type.in?("none", "inherit")

      if body = request["body"]?.try(&.as_h?)
        case body["type"]?.try(&.as_s?)
        when "json"
          json_body_pairs(body["raw"]?.try(&.as_s?) || "", MUSTACHE_VAR).each do |name, value|
            push_param_once(params, Param.new(name, value, "json"))
          end
        when "formencoded", "formdata"
          each_entry(body["form"]?) { |name, value| push_param_once(params, Param.new(name, value, "form")) }
          each_entry(body["files"]?) { |name, _| push_param_once(params, Param.new(name, "", "form")) }
        end
      end

      @result << Endpoint.new(url_path, method, params, Details.new(PathInfo.new(path)))
    end

    # Enabled `{name, value}` entries of a params/headers/form list.
    private def each_entry(list : JSON::Any?, &)
      list.try(&.as_a?).try &.each do |entry|
        next unless name = entry["name"]?.try(&.as_s?).presence
        next if entry["isDisabled"]?.try(&.as_bool?)
        yield name, entry["value"]?.try(&.as_s?) || "", entry
      end
    end
  end
end
