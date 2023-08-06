require "../../models/analyzer"

class AnalyzerSinatra < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{@base_path}/**/*") do |path|
      spawn do
        next if File.directory?(path)
        if File.exists?(path)
          File.open(path, "r") do |file|
            file.each_line do |line|
              line.scan(/get\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "GET")
                end
              end

              line.scan(/post\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "POST")
                end
              end

              line.scan(/put\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "PUT")
                end
              end

              line.scan(/delete\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "DELETE")
                end
              end

              line.scan(/patch\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "PATCH")
                end
              end

              line.scan(/head\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "HEAD")
                end
              end

              line.scan(/options\s+['"](.+?)['"]/) do |match|
                if match.size > 1
                  @result << Endpoint.new("#{@url}#{match[1]}", "OPTIONS")
                end
              end
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_sinatra(options : Hash(Symbol, String))
  instance = AnalyzerSinatra.new(options)
  instance.analyze
end
