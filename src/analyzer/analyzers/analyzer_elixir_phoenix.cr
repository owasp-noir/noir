require "../../models/analyzer"

class AnalyzerElixirPhoenix < Analyzer
  def analyze
    # Source Analysis
    begin
      Dir.glob("#{@base_path}/**/*") do |path|
        next if File.directory?(path)
        if File.exists?(path) && File.extname(path) == ".ex"
          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            last_endpoint = Endpoint.new("", "")
            file.each_line do |line|
              endpoint = line_to_endpoint(line)
              if endpoint.method != ""
                @result << endpoint
                last_endpoint = endpoint
                _ = last_endpoint
              end
            end
          end
        end
      end
    rescue e
      logger.debug e
    end

    @result
  end

  def line_to_endpoint(line : String) : Endpoint
    line.scan(/get\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      @result << Endpoint.new("#{@url}#{match[1]}", "GET")
    end

    line.scan(/post\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      @result << Endpoint.new("#{@url}#{match[1]}", "POST")
    end

    line.scan(/patch\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      @result << Endpoint.new("#{@url}#{match[1]}", "PATCH")
    end

    line.scan(/put\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      @result << Endpoint.new("#{@url}#{match[1]}", "PUT")
    end

    line.scan(/delete\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      @result << Endpoint.new("#{@url}#{match[1]}", "DELETE")
    end

    line.scan(/socket\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
      tmp = Endpoint.new("#{@url}#{match[1]}", "GET")
      tmp.set_protocol("ws")
      @result << tmp
    end

    Endpoint.new("", "")
  end
end

def analyzer_elixir_phoenix(options : Hash(Symbol, String))
  instance = AnalyzerElixirPhoenix.new(options)
  instance.analyze
end
