require "../../models/analyzer"
require "../../minilexers/golang"

class AnalyzerGoBeego < Analyzer
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
                    new_endpoint = Endpoint.new("#{route_path}", line.split(".")[1].split("(")[0].to_s.upcase, details)
                    result << new_endpoint
                    last_endpoint = new_endpoint
                  end
                end
              end

              if line.includes?(".Any(") || line.includes?(".Handler(") || line.includes?(".Router(")
                get_route_path(line, groups).tap do |route_path|
                  if route_path.size > 0
                    new_endpoint = Endpoint.new("#{route_path}", "GET", details)
                    result << new_endpoint
                    last_endpoint = new_endpoint
                  end
                end
              end

              ["GetString", "GetStrings", "GetInt", "GetInt8", "GetUint8", "GetInt16", "GetUint16", "GetInt32", "GetUint32",
               "GetInt64", "GetUint64", "GetBool", "GetFloat"].each do |pattern|
                match = line.match(/#{pattern}\(\"(.*)\"\)/)
                if match
                  param_name = match[1]
                  last_endpoint.params << Param.new(param_name, "", "query")
                end
              end

              if line.includes?("GetCookie(")
                match = line.match(/GetCookie\(\"(.*)\"\)/)
                if match
                  cookie_name = match[1]
                  last_endpoint.params << Param.new(cookie_name, "", "cookie")
                end
              end

              if line.includes?("GetSecureCookie(")
                match = line.match(/GetSecureCookie\(\"(.*)\"\)/)
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

def analyzer_go_beego(options : Hash(String, YAML::Any))
  instance = AnalyzerGoBeego.new(options)
  instance.analyze
end
