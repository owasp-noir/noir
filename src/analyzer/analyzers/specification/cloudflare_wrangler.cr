require "../../../models/analyzer"
require "toml"

module Analyzer::Specification
  class CloudflareWrangler < Analyzer
    METHOD_ANY = "ANY"

    def analyze
      spec_files = CodeLocator.instance.all("cloudflare-wrangler-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          if path.ends_with?(".toml")
            process_toml(content, details)
          else
            process_json(content, details)
          end
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_toml(content : String, details : Details)
      doc = TOML.parse(content)
      routes = doc["routes"]?
      return unless routes
      arr = routes.as_a?
      return unless arr
      arr.each { |entry| emit_toml_route(entry, details) }
    end

    private def process_json(content : String, details : Details)
      # `wrangler.jsonc` allows comments; strip them before parsing.
      doc = JSON.parse(strip_jsonc_comments(content))
      routes = doc["routes"]?
      return unless routes
      arr = routes.as_a?
      return unless arr
      arr.each { |entry| emit_json_route(entry, details) }
    end

    private def emit_toml_route(entry : TOML::Any, details : Details)
      pattern = nil
      zone = nil

      if h = entry.as_h?
        pattern = h["pattern"]?.try(&.as_s?)
        zone = h["zone_name"]?.try(&.as_s?) || h["zone_id"]?.try(&.as_s?)
      elsif s = entry.as_s?
        pattern = s
      end

      register_endpoint(pattern, zone, details)
    end

    private def emit_json_route(entry : JSON::Any, details : Details)
      pattern = nil
      zone = nil

      if h = entry.as_h?
        pattern = h["pattern"]?.try(&.as_s?)
        zone = h["zone_name"]?.try(&.as_s?) || h["zone_id"]?.try(&.as_s?)
      elsif s = entry.as_s?
        pattern = s
      end

      register_endpoint(pattern, zone, details)
    end

    private def register_endpoint(pattern : String?, zone : String?, details : Details)
      return if pattern.nil? || pattern.empty?

      endpoint = Endpoint.new(pattern, METHOD_ANY, details)
      endpoint.add_tag(Tag.new("wrangler-scope", "route", "cloudflare_wrangler_analyzer"))
      endpoint.add_tag(Tag.new("wrangler-zone", zone, "cloudflare_wrangler_analyzer")) if zone && !zone.empty?
      @result << endpoint
    end

    private def strip_jsonc_comments(content : String) : String
      result = String.build do |io|
        in_string = false
        escape = false
        i = 0
        chars = content.chars
        while i < chars.size
          c = chars[i]
          if in_string
            io << c
            if escape
              escape = false
            elsif c == '\\'
              escape = true
            elsif c == '"'
              in_string = false
            end
            i += 1
            next
          end

          if c == '"'
            in_string = true
            io << c
            i += 1
          elsif c == '/' && i + 1 < chars.size && chars[i + 1] == '/'
            # line comment: skip to end of line
            while i < chars.size && chars[i] != '\n'
              i += 1
            end
          elsif c == '/' && i + 1 < chars.size && chars[i + 1] == '*'
            # block comment: skip until */
            i += 2
            while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
              i += 1
            end
            i += 2
          else
            io << c
            i += 1
          end
        end
      end
      result
    end
  end
end
