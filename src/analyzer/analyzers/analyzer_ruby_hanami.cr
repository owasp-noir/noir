require "../../models/analyzer"

class AnalyzerRubyHanami < Analyzer
  def analyze
    # Config Analysis
    path = "#{@base_path}/config/routes.rb"
    if File.exists?(path)
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        last_endpoint = Endpoint.new("", "")
        file.each_line.with_index do |line, index|
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = line_to_endpoint(line, details)
          if endpoint.method != ""
            @result << endpoint
            last_endpoint = endpoint
            _ = last_endpoint
          end
        end
      end
    end

    @result
  end

  def line_to_endpoint(content : String, details : Details) : Endpoint
    content.scan(/get\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "GET", details)
      end
    end

    content.scan(/post\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "POST", details)
      end
    end

    content.scan(/put\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "PUT", details)
      end
    end

    content.scan(/delete\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "DELETE", details)
      end
    end

    content.scan(/patch\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "PATCH", details)
      end
    end

    content.scan(/head\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "HEAD", details)
      end
    end

    content.scan(/options\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{match[1]}", "OPTIONS", details)
      end
    end

    Endpoint.new("", "")
  end
end

def analyzer_ruby_hanami(options : Hash(String, String))
  instance = AnalyzerRubyHanami.new(options)
  instance.analyze
end
