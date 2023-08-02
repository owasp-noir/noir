require "../../models/analyzer"

class AnalyzerDjango < Analyzer
  def analyze
    # Public Dir Analysis
    Dir.glob("#{@base_path}/static/**/*") do |file|
      next if File.directory?(file)
      relative_path = file.sub("#{@base_path}/static/", "")
      @result << Endpoint.new("#{@url}/#{relative_path}", "GET")
    end

    # urls.py Analysis
    if File.exists?(File.join(@base_path, "urls.py"))
      File.open(File.join(@base_path, "urls.py"), "r") do |file|
        file.each_line do |line|
          mapping_paths = mapping_to_path(line)
          mapping_paths.each do |mapping_path|
            @result << Endpoint.new("#{@url}#{mapping_path}", "GET")
          end
        end
      end
    end

    @result
  end

  def mapping_to_path(content : String)
    paths = Array(String).new
    if content.includes?("re_path(r")
      content.strip.split("re_path(r").each do |path|
        if path.includes?(",")
          path = path.split(",")[0]
          path = path.gsub(/['"]/, "")
          path = path.gsub(/ /, "")
          path = path.gsub(/\^/, "")
          paths.push("/#{path}")
        end
      end
    elsif content.includes?("path(")
      content.strip.split("path(").each do |path|
        if path.includes?(",")
          path = path.split(",")[0]
          path = path.gsub(/['"]/, "")
          path = path.gsub(/ /, "")
          paths.push("/#{path}")
        end
      end
    elsif content.includes?("register(r")
      content.strip.split("register(r").each do |path|
        if path.includes?(",")
          path = path.split(",")[0]
          path = path.gsub(/['"]/, "")
          path = path.gsub(/ /, "")
          paths.push("/#{path}")
        end
      end
    end

    paths
  end
end

def analyzer_django(options : Hash(Symbol, String))
  instance = AnalyzerDjango.new(options)
  instance.analyze
end
