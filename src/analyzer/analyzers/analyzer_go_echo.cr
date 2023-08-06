require "../../models/analyzer"

class AnalyzerGoEcho < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".go"
        File.open(path, "r") do |file|
          file.each_line do |line|
            if line.includes?(".GET(") || line.includes?(".POST(") || line.includes?(".PUT(") || line.includes?(".DELETE(")
              get_route_path_go_echo(line).tap do |route_path|
                if route_path.size > 0
                  result << Endpoint.new("#{url}#{route_path}", line.split(".")[1].split("(")[0])
                end
              end
            end
          end
        end
      end
    end
    Fiber.yield

    result
  end

  def get_route_path_go_echo(line : String) : String
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
