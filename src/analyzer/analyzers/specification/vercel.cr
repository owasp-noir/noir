require "../../../models/analyzer"

module Analyzer::Specification
  class Vercel < Analyzer
    ROUTING_GROUP_KEYS = {"beforeFiles", "afterFiles", "fallback"}
    PATTERN_CHARS      = {'*', '^', '$', '(', ')', '[', ']', '{', '}', '|', '+', '?', '\\'}
    METHOD_ANY         = "ANY"

    def analyze
      locator = CodeLocator.instance
      config_files = locator.all("vercel-spec")
      return @result unless config_files.is_a?(Array(String))

      config_files.each do |path|
        next unless File.exists?(path)
        details = Details.new(PathInfo.new(path))
        content = File.read(path, encoding: "utf-8", invalid: :skip)
        begin
          process_config(JSON.parse(content), details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_config(config : JSON::Any, details : Details)
      emit_rules(config["rewrites"]?, "source", "rewrite", details)
      emit_rules(config["redirects"]?, "source", "redirect", details)
      emit_rules(config["routes"]?, "src", "route", details)
      emit_rules(config["headers"]?, "source", "header", details)
    end

    private def emit_rules(node : JSON::Any?, source_key : String, rule_kind : String, details : Details)
      entries_for(node).each do |entry|
        source = entry[source_key]?.try(&.as_s?)
        next if source.nil? || source.empty?

        endpoint = Endpoint.new(source, METHOD_ANY, details)
        endpoint.add_tag(Tag.new("vercel-rule", rule_kind, "vercel_analyzer"))
        endpoint.add_tag(Tag.new("pattern", "vercel_source_matcher", "vercel_analyzer")) if pattern_source?(source)

        destination = entry["destination"]?.try(&.as_s?) || entry["dest"]?.try(&.as_s?)
        if destination
          endpoint.add_tag(Tag.new("vercel-destination", destination, "vercel_analyzer"))
        end

        if rule_kind == "redirect"
          permanent = entry["permanent"]?.try(&.as_bool?) || false
          endpoint.add_tag(Tag.new("redirect-status", permanent ? "301" : "302", "vercel_analyzer"))
        end

        @result << endpoint
      end
    end

    private def entries_for(node : JSON::Any?) : Array(JSON::Any)
      if direct = node.try(&.as_a?)
        return direct
      end

      grouped_entries = [] of JSON::Any
      groups = node.try(&.as_h?)
      return grouped_entries if groups.nil?

      ROUTING_GROUP_KEYS.each do |key|
        if items = groups[key]?.try(&.as_a?)
          grouped_entries.concat(items)
        end
      end

      grouped_entries
    end

    private def pattern_source?(source : String) : Bool
      source.each_char.any? { |char| PATTERN_CHARS.includes?(char) }
    end
  end
end
