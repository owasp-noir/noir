require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Http < CrystalEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end
      lines = mask_crystal_heredocs(lines)

      last_endpoint : Endpoint? = nil

      lines.each_with_index do |line, index|
        endpoint = line_to_endpoint(line)
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          endpoints << endpoint
          last_endpoint = endpoint
        end

        param = line_to_param(line)
        unless param.name.empty?
          if le = last_endpoint
            unless le.method.empty?
              le.push_param(param)
            end
          end
        end
      end

      endpoints
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      if match = content.match(/context\.request\.query_params\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "query")
      end
      if match = content.match(/context\.request\.form_params\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "form")
      end
      if match = content.match(/context\.request\.headers\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "header")
      end
      if match = content.match(/context\.request\.cookies\[[^\]]*["']([^"'\]]+)["']/)
        return Param.new(match[1], "", "cookie")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # method + path combined on same line FIRST (supports the common "if method && path" pattern)
      # This must precede the plain path== scan so a line with both produces the correct verb.
      %w[GET POST PUT DELETE PATCH HEAD OPTIONS].each do |m|
        re = /context\.request\.method\s*(?:==|===)\s*["']#{m}["']\s*&&\s*.*context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']/
        content.scan(re) do |match|
          if match.size > 1
            return Endpoint.new(normalize_crystal_interpolation(match[1]), m)
          end
        end
        re2 = /context\.request\.path\s*(?:==|===)\s*["']([^"']+?)["']\s*&&\s*.*context\.request\.method\s*(?:==|===)\s*["']#{m}["']/
        content.scan(re2) do |match|
          if match.size > 1
            return Endpoint.new(normalize_crystal_interpolation(match[1]), m)
          end
        end
      end

      # if/elsif explicit path match (common in handlers)
      content.scan(/context\.request\.path\s*(?:==|===|\.starts_with\?|\.includes\?)\s*\(?\s*["']([^"']+?)["']/) do |match|
        if match.size > 1
          p = match[1]
          if valid_crystal_route_path?(p)
            return Endpoint.new(normalize_crystal_interpolation(p), "GET")
          end
        end
      end

      # when "/path" (primary bare pattern inside case on .path or method-nested)
      # NOTE: when used inside a `case context.request.method` the method is not known from this line alone;
      # we conservatively emit GET (fixtures use explicit && for non-GET; real code often falls back to GET or
      # handles multiple verbs under the same path case).
      content.scan(/(?:^|[^.\w])when\s+["']([^"']+?)["']/) do |match|
        if match.size > 1
          p = match[1]
          if valid_crystal_route_path?(p)
            return Endpoint.new(normalize_crystal_interpolation(p), "GET")
          end
        end
      end

      Endpoint.new("", "")
    end
  end
end
