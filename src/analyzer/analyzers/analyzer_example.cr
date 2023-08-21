require "../../models/analyzer"

class AnalyzerExample < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path)
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          file.each_line do |_|
          end
        end
      end
    end

    @result
  end
end

def analyzer_example(options : Hash(Symbol, String))
  instance = AnalyzerExample.new(options)
  instance.analyze
end