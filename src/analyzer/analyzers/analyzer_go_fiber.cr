require "../../models/analyzer"

class AnalyzerGoFiber < Analyzer
  def analyze
    # Source Analysis
    public_dirs = [] of (Hash(String, String))
    groups = [] of Hash(String, String)

    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path) && File.extname(path) == ".go"
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            last_endpoint = Endpoint.new("", "")
            file.each_line.with_index do |line, index|
              details = Details.new(PathInfo.new(path, index + 1))
              lexer = GolangLexer.new

              if line.includes?(".Group(")
                map = lexer.tokenize(line)
                before = Token.new(:unknown, "", 0)
                group_name = ""
                group_path = ""
                map.each do |token|
                  if token.type == :assign
                    group_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
                  end

                  if token.type == :string
                    group_path = token.value.to_s
                    groups.each do |group|
                      group.each do |key, value|
                        if before.value.to_s.includes? key
                          group_path = value + group_path
                        end
                      end
                    end
                  end

                  before = token
                end

                if group_name.size > 0 && group_path.size > 0
                  groups << {
                    group_name => group_path,
                  }
                end
              end

              if line.includes?(".Get(") || line.includes?(".Post(") || line.includes?(".Put(") || line.includes?(".Delete(")
                get_route_path(line, groups).tap do |route_path|
                  if route_path.size > 0
                    new_endpoint = Endpoint.new("#{route_path}", line.split(".")[1].split("(")[0].upcase, details)
                    if line.includes?("websocket.New(")
                      new_endpoint.set_protocol("ws")
                    end
                    result << new_endpoint
                    last_endpoint = new_endpoint
                  end
                end
              end

              if line.includes?(".Query(") || line.includes?(".FormValue(")
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

              if line.includes?("GetRespHeader(")
                match = line.match(/GetRespHeader\(\"(.*)\"\)/)
                if match
                  header_name = match[1]
                  last_endpoint.params << Param.new(header_name, "", "header")
                end
              end

              if line.includes?("Vary(")
                match = line.match(/Vary\(\"(.*)\"\)/)
                if match
                  header_value = match[1]
                  last_endpoint.params << Param.new("Vary", header_value, "header")
                end
              end

              if line.includes?("Cookies(")
                match = line.match(/Cookies\(\"(.*)\"\)/)
                if match
                  cookie_name = match[1]
                  last_endpoint.params << Param.new(cookie_name, "", "cookie")
                end
              end
            end
          end
        end
      end
    rescue e
      logger.debug e
    end

    public_dirs.each do |p_dir|
      full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")
      Dir.glob("#{full_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path)
          if p_dir["static_path"].ends_with?("/")
            p_dir["static_path"] = p_dir["static_path"][0..-2]
          end

          details = Details.new(PathInfo.new(path))
          result << Endpoint.new("#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET", details)
        end
      end
    end

    Fiber.yield

    result
  end

  def get_param(line : String) : Param
    param_type = "json"
    if line.includes?("Query")
      param_type = "query"
    end
    if line.includes?("FormValue")
      param_type = "form"
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
        file_path = second[1].gsub("\"", "").gsub(" ", "").gsub(")", "").gsub_repeatedly("//", "/")
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

  def get_route_path(line : String, groups : Array(Hash(String, String))) : String
    lexer = GolangLexer.new
    map = lexer.tokenize(line)
    before = Token.new(:unknown, "", 0)
    map.each do |token|
      if token.type == :string
        final_path = token.value.to_s
        groups.each do |group|
          group.each do |key, value|
            if before.value.to_s.includes? key
              final_path = value + final_path
            end
          end
        end

        return final_path
      end

      before = token
    end

    ""
  end
end

def analyzer_go_fiber(options : Hash(String, YAML::Any))
  instance = AnalyzerGoFiber.new(options)
  instance.analyze
end
