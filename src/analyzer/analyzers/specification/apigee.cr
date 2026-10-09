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
    PATHSUFFIX_RE = /proxy\.pathsuffix\s*(MatchesPath|LikePath|Matches|Like|JavaRegex|StartsWith|EqualsCaseInsensitive|Equals|Is|~~|~\/|=\||==|:=|=|~)\s*"([^"]*)"/i
    VERB_RE       = /request\.verb\s*(?:==|:=|=|EqualsCaseInsensitive|Equals|Is)\s*"([A-Za-z]+)"/i
    REGEX_OPS     = Set{"javaregex", "~~"}
    OR_RE         = /\s*(?:\|\||\bor\b)\s*/i
    NEGATION_RE   = /(?:!|\bnot)\z/i
    # libxml positions are not exposed; a flow's line is found by its name.
    FLOW_LINE      = /<Flow\s+name\s*=\s*["']([^"']*)["']/
    BASE_PATH_LINE = /<BasePath>\s*([^<\s]*)/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::APIGEE_PROXY) do |path, details|
        content = read_file_content(path)
        root = Noir::XmlComments.parse(content, XML::ParserOptions::NONET).first_element_child
        next unless root && root.name == "ProxyEndpoint"
        base = find_child(root, "HTTPProxyConnection").try { |c| find_child(c, "BasePath") }.try(&.content.strip).presence || "/"

        flow_lines = value_lines(content, FLOW_LINE)
        emitted = false
        find_child(root, "Flows").try do |flows|
          each_child(flows, "Flow") do |flow|
            next unless condition = find_child(flow, "Condition").try(&.content)
            flow_name = flow["name"]?
            flow_details = details_at(details, flow_name.try { |n| take_line(flow_lines, n) })

            # Each top-level `or` branch pairs its own path with its own verb.
            disjuncts(condition).each do |branch|
              suffixes = positive_matches(branch, PATHSUFFIX_RE).map do |m|
                REGEX_OPS.includes?(m[1].downcase) ? Noir::URLPath.strip_regex_anchors(m[2]) : m[2]
              end
              verbs = positive_matches(branch, VERB_RE).map(&.[1].upcase).uniq!
              next if suffixes.empty? && verbs.empty?

              emitted = true
              urls = suffixes.empty? ? [base] : suffixes.map { |suffix| Noir::URLPath.join(base, suffix) }
              emit(urls, verbs, flow_name, flow_details)
            end
          end
        end
        emit([base], [] of String, nil, details_at(details, take_line(value_lines(content, BASE_PATH_LINE), base))) unless emitted
      end

      @result
    end

    # `condition` split on its top-level (unparenthesised, unquoted) `or` / `||`.
    private def disjuncts(condition : String) : Array(String)
      parts = [] of String
      depth = 0
      quoted = false
      start = 0
      i = 0
      while i < condition.bytesize
        byte = condition.to_slice[i]
        if byte == '"'.ord
          quoted = !quoted
        elsif !quoted && byte == '('.ord
          depth += 1
        elsif !quoted && byte == ')'.ord
          depth -= 1
        elsif !quoted && depth == 0 && (sep = OR_RE.match_at_byte_index(condition, i, Regex::MatchOptions::ANCHORED))
          parts << condition.byte_slice(start, i - start)
          start = i = sep.byte_end(0)
          next
        end
        i += 1
      end
      parts << condition.byte_slice(start, condition.bytesize - start)
    end

    # Matches of `re` in `branch` that are not negated by a preceding `!` / `not`.
    private def positive_matches(branch : String, re : Regex) : Array(Regex::MatchData)
      branch.scan(re).reject do |m|
        branch.byte_slice(0, m.byte_begin(0)).rstrip.rstrip('(').rstrip.matches?(NEGATION_RE)
      end
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
