require "../../models/analyzer"

class AnalyzerRubyHanami < Analyzer
  def analyze
    # Config Analysis
    if File.exists?("#{@base_path}/config/routes.rb")
      File.open("#{@base_path}/config/routes.rb", "r", encoding: "utf-8", invalid: :skip) do |file|
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

    @result
  end

  def line_to_endpoint(content : String) : Endpoint
    content.scan(/get\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "GET")
      end
    end

    content.scan(/post\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "POST")
      end
    end

    content.scan(/put\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "PUT")
      end
    end

    content.scan(/delete\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "DELETE")
      end
    end

    content.scan(/patch\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "PATCH")
      end
    end

    content.scan(/head\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "HEAD")
      end
    end

    content.scan(/options\s+['"](.+?)['"]/) do |match|
      if match.size > 1
        return Endpoint.new("#{@url}#{match[1]}", "OPTIONS")
      end
    end

    Endpoint.new("", "")
  end
end

def analyzer_ruby_hanami(options : Hash(Symbol, String))
  instance = AnalyzerRubyHanami.new(options)
  instance.analyze
end
