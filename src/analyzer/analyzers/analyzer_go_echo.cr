require "../../models/analyzer"

class AnalyzerGoEcho < Analyzer
  def analyze
    # Source Analysis
    public_dirs = [] of (Hash(String, String))
    Dir.glob("#{base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".go"
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          last_endpoint = Endpoint.new("", "")
          file.each_line do |line|
            if line.includes?(".GET(") || line.includes?(".POST(") || line.includes?(".PUT(") || line.includes?(".DELETE(")
              get_route_path(line).tap do |route_path|
                if route_path.size > 0
                  new_endpoint = Endpoint.new("#{url}#{route_path}", line.split(".")[1].split("(")[0])
                  result << new_endpoint
                  last_endpoint = new_endpoint
                end
              end
            end

            if line.includes?("Param(") || line.includes?("FormValue(")
              get_param(line).tap do |param|
                if param.name.size > 0 && last_endpoint.method != ""
                  last_endpoint.params << param
                end
              end
            end

            if line.includes?("Static(")
              get_static_path(line).tap do |static_path|
                if static_path.size > 0
                  public_dirs << static_path
                end
              end
            end
          end
        end
      end
    end

    public_dirs.each do |p_dir|
      full_path = (base_path + "/" + p_dir["file_path"]).gsub("//", "/")
      Dir.glob("#{full_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path)
          if p_dir["static_path"].ends_with?("/")
            p_dir["static_path"] = p_dir["static_path"][0..-2]
          end

          result << Endpoint.new("#{url}#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET")
        end
      end
    end

    Fiber.yield

    result
  end

  def get_param(line : String) : Param
    param_type = "json"
    if line.includes?("QueryParam")
      param_type = "query"
    end
    if line.includes?("FormValue")
      param_type = "body"
    end

    first = line.strip.split("(")
    if first.size > 1
      second = first[1].split(")")
      if second.size > 1
        param_name = second[0].gsub("\"", "")
        rtn = Param.new(param_name, "", param_type)

        return rtn
      end
    end

    Param.new("", "", "")
  end

  def get_static_path(line : String) : Hash(String, String)
    first = line.strip.split("(")
    if first.size > 1
      second = first[1].split(",")
      if second.size > 1
        static_path = second[0].gsub("\"", "")
        file_path = second[1].gsub("\"", "").gsub(" ", "").gsub(")", "")
        rtn = {
          "static_path" => static_path,
          "file_path"   => file_path,
        }

        return rtn
      end
    end

    {
      "static_path" => "",
      "file_path"   => "",
    }
  end

  def get_route_path(line : String) : String
    first = line.strip.split("(")
    if first.size > 1
      second = first[1].split(",")
      if second.size > 1
        route_path = second[0].gsub("\"", "")
        return route_path
      end
    end

    ""
  end
end

def analyzer_go_echo(options : Hash(Symbol, String))
  instance = AnalyzerGoEcho.new(options)
  instance.analyze
end
