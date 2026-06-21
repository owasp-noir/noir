require "../../../models/analyzer"
require "set"

module Analyzer::Specification
  class Traefik < Analyzer
    def analyze
      locator = CodeLocator.instance
      files = locator.all("traefik-spec")
      seen = Set(String).new

      if files.is_a?(Array(String))
        files.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)

          begin
            if path.ends_with?(".toml")
              process_toml(content, details, seen)
            else
              process_yaml(content, details, seen)
            end
          rescue e
            @logger.debug "Exception processing #{path}"
            @logger.debug_sub e
          end
        end
      end

      @result
    end

    private def process_yaml(content : String, details : Details, seen : Set(String))
      docs = split_yaml_documents(content)
      docs.each do |doc|
        next if doc.strip.empty?
        begin
          data = YAML.parse(doc)
          extract_dynamic_config_rules(data).each { |rule| parse_rule(rule, details, seen) }
          extract_compose_label_rules(data).each { |rule| parse_rule(rule, details, seen) }
          extract_ingress_route_rules(data).each { |rule| parse_rule(rule, details, seen) }
        rescue e
          logger.debug "Failed to parse Traefik YAML document: #{e}"
        end
      end
    end

    private def process_toml(content : String, details : Details, seen : Set(String))
      current_section = ""

      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        if section = stripped.match(/^\[(.+)\]$/)
          current_section = section[1]
          next
        end

        next unless current_section.starts_with?("http.routers.")

        if rule_match = stripped.match(/^rule\s*=\s*["'](.*)["']\s*$/)
          parse_rule(unescape_toml_string(rule_match[1]), details, seen)
        end
      end
    end

    private def split_yaml_documents(content : String) : Array(String)
      docs = content.split(/^---\s*$/)
      docs.empty? ? [content] : docs
    end

    private def extract_dynamic_config_rules(data : YAML::Any) : Array(String)
      rules = [] of String
      return rules unless root = data.as_h?

      http = root[YAML::Any.new("http")]?
      return rules unless http_h = http.try(&.as_h?)
      routers = http_h[YAML::Any.new("routers")]?
      return rules unless routers_h = routers.try(&.as_h?)

      routers_h.each_value do |router_any|
        next unless router = router_any.as_h?
        rule = router[YAML::Any.new("rule")]?.try(&.to_s)
        rules << rule if rule
      end

      rules
    end

    private def extract_compose_label_rules(data : YAML::Any) : Array(String)
      rules = [] of String
      return rules unless root = data.as_h?
      services = root[YAML::Any.new("services")]?
      return rules unless services_h = services.try(&.as_h?)

      services_h.each_value do |service_any|
        next unless service = service_any.as_h?
        labels = service[YAML::Any.new("labels")]?
        next if labels.nil?

        if labels_h = labels.try(&.as_h?)
          labels_h.each do |k, v|
            key = k.to_s
            next unless traefik_rule_label?(key)
            rules << v.to_s
          end
        elsif labels_a = labels.try(&.as_a?)
          labels_a.each do |entry|
            value = entry.to_s
            next unless match = value.match(/^(traefik\.http\.routers\.[^.]+\.rule)\s*=\s*(.+)$/)
            key = match[1]
            next unless traefik_rule_label?(key)
            rules << strip_quotes(match[2].strip)
          end
        end
      end

      rules
    end

    private def extract_ingress_route_rules(data : YAML::Any) : Array(String)
      rules = [] of String
      return rules unless root = data.as_h?

      kind = root[YAML::Any.new("kind")]?.try(&.to_s) || ""
      return rules unless kind == "IngressRoute"

      spec = root[YAML::Any.new("spec")]?
      return rules unless spec_h = spec.try(&.as_h?)
      routes = spec_h[YAML::Any.new("routes")]?
      return rules unless routes_a = routes.try(&.as_a?)

      routes_a.each do |route_any|
        next unless route = route_any.as_h?
        match = route[YAML::Any.new("match")]?.try(&.to_s)
        rules << match if match
      end

      rules
    end

    private def traefik_rule_label?(key : String) : Bool
      key.starts_with?("traefik.http.routers.") && key.ends_with?(".rule")
    end

    private def parse_rule(rule : String, details : Details, seen : Set(String))
      alternatives = split_top_level(rule, "||")
      alternatives.each do |alt|
        methods = [] of String
        paths = [] of String

        scan_matchers(alt) do |name, args|
          case name.downcase
          when "path", "pathprefix", "pathregexp"
            args.each { |arg| paths << normalize_path(arg) }
          when "method"
            args.each { |arg| methods << arg.upcase }
          end
        end

        paths = ["/"] of String if paths.empty?
        methods = ["GET"] of String if methods.empty?

        paths.each do |path|
          methods.each do |method|
            key = "#{method}::#{path}"
            next if seen.includes?(key)
            seen << key
            @result << Endpoint.new(path, method, [] of Param, details)
          end
        end
      end
    end

    private def scan_matchers(expression : String, & : String, Array(String) ->)
      expression.scan(/([A-Za-z]+)\s*\(([^)]*)\)/) do |match|
        next unless match.size >= 3
        name = match[1]
        args = extract_quoted_values(match[2])
        yield name, args unless args.empty?
      end
    end

    private def extract_quoted_values(input : String) : Array(String)
      values = [] of String
      input.scan(/`([^`]*)`|'([^']*)'|"([^"]*)"/) do |m|
        next unless m.size >= 4
        value = if !m[1].empty?
                  m[1]
                elsif !m[2].empty?
                  m[2]
                else
                  m[3]
                end
        values << value unless value.empty?
      end
      values
    end

    private def split_top_level(input : String, delimiter : String) : Array(String)
      parts = [] of String
      current = ""
      depth = 0
      i = 0

      while i < input.size
        ch = input[i]
        if ch == '('
          depth += 1
          current += ch.to_s
          i += 1
          next
        elsif ch == ')'
          depth -= 1 if depth > 0
          current += ch.to_s
          i += 1
          next
        end

        # `i` is a CHAR index (input[i]); use char-based slicing, not byte_slice,
        # so a multi-byte char before a `||` doesn't desync delimiter detection.
        if depth == 0 && input[i, delimiter.size]? == delimiter
          parts << current.strip unless current.strip.empty?
          current = ""
          i += delimiter.size
          next
        end

        current += ch.to_s
        i += 1
      end

      parts << current.strip unless current.strip.empty?
      parts.reject(&.empty?)
    end

    private def normalize_path(path : String) : String
      cleaned = path.strip
      return "/" if cleaned.empty?
      cleaned.starts_with?('/') ? cleaned : "/#{cleaned}"
    end

    private def strip_quotes(value : String) : String
      return value[1...-1] if value.starts_with?('"') && value.ends_with?('"') && value.size >= 2
      return value[1...-1] if value.starts_with?('\'') && value.ends_with?('\'') && value.size >= 2
      value
    end

    private def unescape_toml_string(value : String) : String
      value.gsub("\\\"", "\"").gsub("\\\\", "\\")
    end
  end
end
