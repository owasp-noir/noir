require "../../engines/specification_engine"

module Analyzer::Specification
  # KrakenD: each `endpoints[]` entry publishes `endpoint` for `method`
  # (GET when omitted). `input_query_strings` / `input_headers` are the only
  # query strings and headers KrakenD forwards, so they are the endpoint's
  # params; the `*` wildcard names none.
  class Krakend < SpecificationEngine
    analyzer_for "krakend"

    ENDPOINT_LINE = /"endpoint"\s*:\s*"([^"]*)"/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::KRAKEND_SPEC) do |path, details|
        content = read_file_content(path)
        next unless endpoints = parse_json_lenient(content).as_h?.try(&.["endpoints"]?).try(&.as_a?)
        lines = first_value_lines(content, ENDPOINT_LINE)
        endpoints.each { |entry| emit(entry, details, lines) }
      end

      @result
    end

    private def emit(entry : JSON::Any, details : Details, lines : Hash(String, Int32))
      return unless entry_h = entry.as_h?
      return unless url = entry_h["endpoint"]?.try(&.as_s?).presence

      params = [] of Param
      json_strings(entry_h["input_query_strings"]?).each { |name| add_param(params, name, "query") unless name == "*" }
      json_strings(entry_h["input_headers"]?).each { |name| add_param(params, name, "header") unless name == "*" }
      method = entry_h["method"]?.try(&.as_s?).presence.try(&.upcase) || "GET"

      endpoint = Endpoint.new(url, method, params, details_at(details, lines[url]?))
      entry_h["backend"]?.try(&.as_a?).try(&.each do |backend|
        next unless pattern = backend.as_h?.try(&.["url_pattern"]?.try(&.as_s?)).presence
        endpoint.add_tag(Tag.new("krakend-backend", pattern, "krakend_analyzer"))
      end)
      @result << endpoint
    end
  end
end
