require "../../utils/utils.cr"

def analyzer_php_pure(options : Hash(Symbol, String))
  result = [] of Endpoint
  base_path = options[:base]
  url = options[:url]

  # Source Analysis
  Dir.glob("#{base_path}/**/*") do |path|
    next if File.directory?(path)
    if base_path[-1].to_s == "/"
      relative_path = path.sub("#{base_path}", "").sub("./", "").sub("//", "/")
    else
      relative_path = path.sub("#{base_path}/", "").sub("./", "").sub("//", "/")
    end
    relative_path = remove_start_slash(relative_path)

    if File.exists?(path)
      File.open(path, "r") do |file|
        param_type = "form"
        params_query = [] of Param
        params_body = [] of Param
        methods = [] of String

        file.each_line do |line|
          match = line.strip.match(%r{.*\$_(.*?)\['(.*?)'\];})

          if match
            method = match[1]
            param_name = match[2]

            methods = methods | [method]
            params_query << Param.new(param_name, "string", "query")
            params_body << Param.new(param_name, "string", "form")
          end
        rescue
          next
        end
        methods.each do |method|
          result << Endpoint.new("#{url}/#{relative_path}", method, params_body)
        end
        result << Endpoint.new("#{url}/#{relative_path}", "GET", params_query)
      end
    end
  end

  result
end
