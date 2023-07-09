require "../../models/analyzer"

class AnalyzerDjango < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{base_path}/**/*") do |path|
      spawn do
        next if File.directory?(path)
        if File.exists?(path) && File.extname(path) == ".py"
          File.open(path, "r") do |file|
            file.each_line do |_|
              # TODO
            end
          end
        end
      end
    end
    Fiber.yield

    @result
  end
end

def analyzer_django(options : Hash(Symbol, String))
  instance = AnalyzerDjango.new(options)
  instance.analyze
end
