def analyzer_spring(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    next if File.directory?(path)

    if File.exists?(path)
      File.open(path, "r") do |file|
        file.each_line do |line|
          if line.includes? "RequestMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "GET")
          end
          if line.includes? "PostMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "POST")
          end
          if line.includes? "PutMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "PUT")
          end
          if line.includes? "DeleteMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "DELETE")
          end
          if line.includes? "PatchMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "PATCH")
          end
          if line.includes? "GetMapping"
            path_with_slash = mapping_to_path(line)
            result << Endpoint.new("#{url}#{path_with_slash}", "GET")
          end
        end
      end
    end
  end

  result
end

def mapping_to_path(content : String)
  splited_line = content.strip.split("(")
  if splited_line.size > 1
    line = splited_line[1].gsub(/"|\)/, "")
    if line[0].to_s == '/'
      return line
    else
      return "/#{line}"
    end
  end
  ""
end

def extract_param(content : String)
  # TODO
  # case1 -> @RequestParam("a")
  # case2 -> String a = param.get("a");
  # case3 -> String a = request.getParameter("a");
  # case4 -> (PATH) @PathVariable("a")
end
