require "../../models/analyzer"

class AnalyzerFlask < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".py"
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line do |line|
            line.strip.scan(/@app\.route\((.*)\)/) do |match|
              if match.size > 0
                splited = match[0].split("(")
                if splited.size > 1
                  endpoint_path = splited[1].gsub("\"", "").gsub("'", "").gsub(")", "").gsub(" ", "")
                  result << Endpoint.new("#{url}#{endpoint_path}", "GET")
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
end

def analyzer_flask(options : Hash(Symbol, String))
  instance = AnalyzerFlask.new(options)
  instance.analyze
end
