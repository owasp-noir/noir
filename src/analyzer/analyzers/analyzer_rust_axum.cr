require "../../models/analyzer"

class AnalyzerRustAxum < Analyzer
  def analyze
    # Source Analysis
    pattern = /\.route\("([^"]+)",\s*([^)]+)\)/

    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path) && File.extname(path) == ".rs"
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file.each_line do |line|
              if line.includes? ".route("
                match = line.match(pattern)
                if match
                  begin
                    route_argument = match[1]
                    callback_argument = match[2]
                    result << Endpoint.new(route_argument, callback_to_method(callback_argument))
                  rescue
                  end
                end
              end
            end
          end
        end
      end
    rescue e
    end

    result
  end

  def callback_to_method(str)
    method = str.split("(").first
    if !["get", "post", "put", "delete"].includes?(method)
      method = "get"
    end

    method.upcase
  end
end

def analyzer_rust_axum(options : Hash(Symbol, String))
  instance = AnalyzerRustAxum.new(options)
  instance.analyze
end
