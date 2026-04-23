require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Grape < RubyEngine
    GRAPE_VERBS = ["get", "post", "put", "delete", "patch", "head", "options"]

    def analyze
      parallel_file_scan do |path|
        next unless path.ends_with?(".rb")
        content = read_file_content(path)
        next unless content.includes?("Grape::API")
        process_file(path, content)
      end

      @result
    end

    private def process_file(path : String, content : String) : Nil
      prefix_segments = [] of String
      block_kinds = [] of Symbol
      class_prefix = ""
      pending_params = [] of String
      in_params_block = false
      last_endpoint : Endpoint? = nil

      content.each_line.with_index do |raw_line, index|
        line = raw_line
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?('#')

        if in_params_block
          if stripped == "end" || stripped.starts_with?("end ")
            in_params_block = false
            next
          end
          stripped.scan(/(?:requires|optional)\s+:([\w]+)/) do |m|
            pending_params << m[1] if m.size > 1
          end
          next
        end

        if stripped == "params do" || stripped.starts_with?("params do")
          in_params_block = true
          next
        end

        if m = stripped.match(/^(?:prefix|route_prefix)\s+['":]([\w\/]+)['"]?/)
          class_prefix = m[1].to_s
          next
        end

        if m = stripped.match(/^(?:resource|resources|namespace|group|segment)\s+['":]([\w]+)['"]?\s+do\b/)
          prefix_segments << m[1].to_s
          block_kinds << :prefix
          next
        end

        verb_handled = false
        GRAPE_VERBS.each do |verb|
          if m = stripped.match(/^#{verb}\b(?:\s+['"]([^'"]+)['"])?(?:\s*,[^#]*?)?\s*do\b/)
            raw_path = (m[1]? || "").to_s
            ep_path = build_path(class_prefix, prefix_segments, raw_path)
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(ep_path, verb.upcase, details)

            extract_path_params(raw_path).each do |pn|
              endpoint.push_param(Param.new(pn, "", "path"))
            end

            pending_params.each do |pn|
              next if raw_path.includes?(":#{pn}")
              endpoint.push_param(Param.new(pn, "", "json"))
            end
            pending_params.clear

            @result << endpoint
            last_endpoint = endpoint
            block_kinds << :other
            verb_handled = true
            break
          end

          if m = stripped.match(/^#{verb}\s+do\b/)
            ep_path = build_path(class_prefix, prefix_segments, "")
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(ep_path, verb.upcase, details)

            pending_params.each do |pn|
              endpoint.push_param(Param.new(pn, "", "json"))
            end
            pending_params.clear

            @result << endpoint
            last_endpoint = endpoint
            block_kinds << :other
            verb_handled = true
            break
          end
        end

        next if verb_handled

        if le = last_endpoint
          line.scan(/\bparams\[:([\w]+)\]/) do |match|
            if match.size > 1
              le.push_param(Param.new(match[1], "", "query"))
            end
          end
          line.scan(/\bparams\[['"](\w+)['"]\]/) do |match|
            if match.size > 1
              le.push_param(Param.new(match[1], "", "query"))
            end
          end
          line.scan(/\bheaders\[['"]([^'"]+)['"]\]/) do |match|
            if match.size > 1
              le.push_param(Param.new(match[1], "", "header"))
            end
          end
          line.scan(/\bcookies\[['"]?:?([\w-]+)['"]?\]/) do |match|
            if match.size > 1
              le.push_param(Param.new(match[1], "", "cookie"))
            end
          end
        end

        if stripped.matches?(/\bdo(\s*\|[^|]*\|)?\s*$/)
          block_kinds << :other
        end

        if stripped == "end" || stripped.starts_with?("end ") || stripped.starts_with?("end#")
          popped = block_kinds.pop?
          if popped == :prefix && !prefix_segments.empty?
            prefix_segments.pop
          end
        end
      end
    end

    private def build_path(class_prefix : String, prefix_segments : Array(String), raw : String) : String
      parts = [] of String
      parts << class_prefix unless class_prefix.empty?
      prefix_segments.each { |s| parts << s }
      unless raw.empty?
        cleaned = raw.starts_with?('/') ? raw[1..] : raw
        parts << cleaned unless cleaned.empty?
      end
      joined = parts.reject(&.empty?).join("/")
      path = joined.empty? ? "/" : "/#{joined}"
      path.gsub(/:([a-zA-Z_][\w]*)/) { "{#{$~[1]}}" }
    end

    private def extract_path_params(raw : String) : Array(String)
      names = [] of String
      raw.scan(/:([a-zA-Z_][\w]*)/) do |m|
        names << m[1] if m.size > 1
      end
      names
    end
  end
end
