require "../../engines/specification_engine"

module Analyzer::Specification
  # Ocelot (.NET API gateway): `Routes[]` (`ReRoutes[]` before Ocelot 16)
  # publish `UpstreamPathTemplate` for the `UpstreamHttpMethod` verbs, or for
  # any verb when that list is empty. `Aggregates[]` are GET-only.
  class Ocelot < SpecificationEngine
    analyzer_for "ocelot"

    TEMPLATE_LINE = /"UpstreamPathTemplate"\s*:\s*"([^"]*)"/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::OCELOT_SPEC) do |path, details|
        # Comment-free and line-preserving, so a commented-out route has no line.
        json = strip_jsonc(read_file_content(path))
        root = parse_json_lenient(json).as_h?
        next unless root
        lines = value_lines(json, TEMPLATE_LINE)

        {"Routes", "ReRoutes"}.each do |key|
          root[key]?.try(&.as_a?).try(&.each { |route| emit(route, details, lines, nil) })
        end
        root["Aggregates"]?.try(&.as_a?).try(&.each { |route| emit(route, details, lines, "GET") })
      end

      @result
    end

    private def emit(route : JSON::Any, details : Details, lines : Hash(String, Array(Int32)), fixed_method : String?)
      return unless route_h = route.as_h?
      return unless template = route_h["UpstreamPathTemplate"]?.try(&.as_s?).presence

      methods = fixed_method ? [fixed_method] : json_strings(route_h["UpstreamHttpMethod"]?).map(&.upcase)
      methods = ["ANY"] if methods.empty?
      downstream = route_h["DownstreamPathTemplate"]?.try(&.as_s?).presence
      hosts = json_strings(route_h["UpstreamHost"]?)
      line = take_line(lines, template)

      methods.each do |method|
        endpoint = Endpoint.new(template, method, details_at(details, line))
        endpoint.add_tag(Tag.new("ocelot-downstream", downstream, "ocelot_analyzer")) if downstream
        endpoint.add_tag(Tag.new("ocelot-host", hosts.join(", "), "ocelot_analyzer")) unless hosts.empty?
        @result << endpoint
      end
    end
  end
end
