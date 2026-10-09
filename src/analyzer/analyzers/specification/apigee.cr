require "../../engines/specification_engine"
require "../../../utils/url_path"
require "../../../utils/xml_comments"

module Analyzer::Specification
  # Apigee proxy endpoints: `HTTPProxyConnection/BasePath` is the public prefix
  # and each conditional `Flows/Flow` names a resource under it through
  # `proxy.pathsuffix` and `request.verb` conditions. A proxy with no such flow
  # forwards everything under its base path, so the base path alone is emitted.
  class Apigee < SpecificationEngine
    analyzer_for "apigee"

    # Longer operators first, so `=|` (StartsWith) is not read as `=`.
    PATHSUFFIX_RE = /proxy\.pathsuffix\s*(MatchesPath|Matches|Like|JavaRegex|StartsWith|Equals|Is|~~|~\/|=\||==|=|~)\s*"([^"]*)"/i
    VERB_RE       = /request\.verb\s*(?:==|=|Equals|Is)\s*"([A-Za-z]+)"/i
    REGEX_OPS     = Set{"javaregex", "~~"}
    # libxml positions are not exposed; a flow's line is found by its name.
    FLOW_LINE      = /<Flow\s+name\s*=\s*["']([^"']*)["']/
    BASE_PATH_LINE = /<BasePath>\s*([^<\s]*)/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::APIGEE_PROXY) do |path, details|
        content = read_file_content(path)
        root = Noir::XmlComments.parse(content, XML::ParserOptions::NONET).first_element_child
        next unless root && root.name == "ProxyEndpoint"
        base = find_child(root, "HTTPProxyConnection").try { |c| find_child(c, "BasePath") }.try(&.content.strip).presence || "/"

        flow_lines = first_value_lines(content, FLOW_LINE)
        emitted = false
        find_child(root, "Flows").try do |flows|
          each_child(flows, "Flow") do |flow|
            next unless condition = find_child(flow, "Condition").try(&.content)
            suffixes = condition.scan(PATHSUFFIX_RE).map do |m|
              REGEX_OPS.includes?(m[1].downcase) ? Noir::URLPath.strip_regex_anchors(m[2]) : m[2]
            end
            verbs = condition.scan(VERB_RE).map(&.[1].upcase).uniq!
            next if suffixes.empty? && verbs.empty?

            emitted = true
            urls = suffixes.empty? ? [base] : suffixes.map { |suffix| Noir::URLPath.join(base, suffix) }
            flow_name = flow["name"]?
            emit(urls, verbs, flow_name, details_at(details, flow_name.try { |n| flow_lines[n]? }))
          end
        end
        emit([base], [] of String, nil, details_at(details, first_value_lines(content, BASE_PATH_LINE)[base]?)) unless emitted
      end

      @result
    end

    private def emit(urls : Array(String), verbs : Array(String), flow_name : String?, details : Details)
      verbs = ["ANY"] if verbs.empty?
      urls.each do |url|
        verbs.each do |verb|
          endpoint = Endpoint.new(url, verb, details)
          endpoint.add_tag(Tag.new("apigee-flow", flow_name, "apigee_analyzer")) if flow_name
          @result << endpoint
        end
      end
    end
  end
end
