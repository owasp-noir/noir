require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Fasthttp < Analyzer
    def analyze
      # Source Analysis
      begin
        Dir.glob("#{base_path}/**/*.go") do |path|
          next if File.directory?(path)
          if File.exists?(path)
            File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
              last_endpoint = Endpoint.new("", "")
              file.each_line.with_index do |line, index|
                details = Details.new(PathInfo.new(path, index + 1))

                # Detect fasthttp route patterns
                endpoint = analyze_route_line(line, details)
                if endpoint.method != ""
                  result << endpoint
                  last_endpoint = endpoint
                end

                # Detect parameter usage in current context
                params = analyze_param_line(line)
                params.each do |param|
                  if param.name.size > 0 && last_endpoint.method != ""
                    # Check for duplicates before adding
                    unless last_endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
                      last_endpoint.params << param
                    end
                  end
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    private def analyze_route_line(line : String, details : Details) : Endpoint
      # Pattern 1: Direct handler registration with router
      # router.GET("/path", handler) or router.POST("/path", handler)
      if match = line.match(/(?:router|r|app|server)\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"([^"]+)"\s*,/)
        path = match[1]
        method = extract_method_from_router_call(line)
        return Endpoint.new(path, method, details)
      end

      # Pattern 2: fasthttprouter patterns
      # router.GET("/path", handler)
      if match = line.match(/\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"([^"]+)"\s*,/)
        path = match[1]
        method = extract_method_from_router_call(line)
        return Endpoint.new(path, method, details)
      end

      # Pattern 3: Direct fasthttp.ListenAndServe with switch statements for routes
      # This would require more complex analysis, for now we focus on router patterns

      Endpoint.new("", "")
    end

    private def extract_method_from_router_call(line : String) : String
      if match = line.match(/\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)/)
        match[0].gsub(".", "").upcase
      else
        ""
      end
    end

    private def analyze_param_line(line : String) : Array(Param)
      params = [] of Param

      # QueryArgs().Peek("param") or QueryArgs().Get("param")
      line.scan(/(?:QueryArgs|PostArgs)\(\)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        param_type = line.includes?("QueryArgs") ? "query" : "form"
        params << Param.new(param_name, "", param_type)
      end

      # ctx.QueryArgs().Peek("param")
      line.scan(/ctx\.(?:QueryArgs|PostArgs)\(\)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        param_type = line.includes?("QueryArgs") ? "query" : "form"
        params << Param.new(param_name, "", param_type)
      end

      # Request.Header.Peek("header")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "header")
      end

      # Cookie access: ctx.Request.Header.Cookie("name")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.Cookie\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "cookie")
      end

      # Form values: ctx.FormValue("param")
      line.scan(/ctx\.FormValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "form")
      end

      # UserValue for path parameters: ctx.UserValue("param")
      line.scan(/ctx\.UserValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end

      params
    end
  end
end
