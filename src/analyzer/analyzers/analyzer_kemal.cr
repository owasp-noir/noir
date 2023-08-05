require "../../models/analyzer"

class AnalyzerKemal < Analyzer
  def analyze
    # Source Analysis
    Dir.glob("#{@base_path}/**/*") do |path|
      next if File.directory?(path)
      if File.exists?(path) && File.extname(path) == ".cr" && !path.includes?("spec") && !path.includes?("lib")
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

    @result
  end
end

def analyzer_kemal(options : Hash(Symbol, String))
  instance = AnalyzerKemal.new(options)
  instance.analyze
end
