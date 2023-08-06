require "../../models/analyzer"

class AnalyzerExample < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path)
        File.open(path, "r") do |file|
          file.each_line do |_|
          end
        end
      end
    end

    @result
  end
end
