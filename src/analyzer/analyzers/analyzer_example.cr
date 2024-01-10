require "../../models/analyzer"

class AnalyzerExample < Analyzer
  def analyze
    # Source Analysis
    begin
      Dir.glob("#{base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path)
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            file.each_line.with_index do |_, _|
              # For example (Add endpoint to result)
              # endpoint = Endpoint.new("/", "GET")
              # details = Details.new(PathInfo.new(path, index + 1))
              # endpoint.set_details(details)
              # @result << endpoint
            end
          end
        end
      end
    rescue e
      logger.debug e
    end

    @result
  end
end

def analyzer_example(options : Hash(Symbol, String))
  instance = AnalyzerExample.new(options)
  instance.analyze
end
