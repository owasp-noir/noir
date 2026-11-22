require "./csharp_decl_parser"
require "../utils/top_level_split"

module Noir
  # Request binding configured outside handler declarations, for one project.
  class CSharpMinimalApiConfig
    getter services = Set(String).new
    getter readers = Set(Tuple(String, String)).new
    getter? versioning = false
    getter? unknown_reader = false
    @reader_assigned = false

    VERSION_REGISTRATION = /\.\s*AddApiVersioning\s*\(/
    VERSION_OPTIONS      = /\.\s*(?:Post)?Configure\s*<\s*(?:[\w.]+\.)?ApiVersioningOptions\s*>\s*\(/
    READER_ASSIGNMENT    = /\bApiVersionReader\s*=\s*(?!=|>)/
    SERVICE_REGISTRATION = /\.\s*(?:Try)?Add(?:Singleton|Scoped|Transient)\s*(?:<\s*([\w.]+(?:<[^<>]*>)?)\s*(?=[,>])|\(\s*typeof\(\s*([\w.]+)\s*\)|\(\s*new\s+([\w.]+)\s*\()/
    VERSION_METADATA     = /\.\s*(?:Has(?:Deprecated)?ApiVersion|MapToApiVersion|WithApiVersionSet)\s*\(/
    NEUTRAL_METADATA     = /\.\s*IsApiVersionNeutral\s*\(/

    def read(content : String)
      return unless content.includes?("ApiVersion") || content.matches?(SERVICE_REGISTRATION)
      lexer = CSharpLexer.new(content)
      masked = lexer.masked_source
      masked.scan(SERVICE_REGISTRATION) { |m| @services << (m[1]? || m[2]? || m[3]) }
      @versioning ||= masked.matches?(VERSION_REGISTRATION)
      masked.scan(Regex.union(VERSION_REGISTRATION, VERSION_OPTIONS)) do |m|
        open = m.end - 1
        close = lexer.matching_delimiter(open)
        unless close
          @unknown_reader = true
          next
        end
        arg = masked[open + 1...close].strip
        next if arg.empty?
        # A callback that passes the options to other code can replace the reader.
        callback = arg.match(/\A\(?\s*(\w+)\s*\)?\s*=>/)
        @unknown_reader = true if callback.nil? || arg[callback.end..].matches?(/\b#{Regex.escape(callback[1])}\b(?!\s*\.)/)
      end
      masked.scan(READER_ASSIGNMENT) do |m|
        @unknown_reader = true if @reader_assigned
        @reader_assigned = true
        finish = lexer.statement_end(m.end)
        expression = lexer.code_source[m.end...finish].strip.rchop(';').strip
        # An expression-bodied options callback ends at the registration's
        # closing parenthesis, outside the reader constructor.
        if (open = masked.index('(', m.end)) && open < finish
          if close = lexer.matching_delimiter(open)
            tail = masked[close + 1...finish]
            expression = lexer.code_source[m.end..close].strip if tail.matches?(/\A[\s);]*\z/)
          end
        end
        read_reader(expression)
      end
    end

    def finish
      if @versioning && !@reader_assigned && !@unknown_reader
        @readers << {"query", "api-version"}
      end
    end

    private def read_reader(expression : String)
      if combined = expression.match(/\A(?:[\w.]+\.)?ApiVersionReader\.Combine\s*\(([\s\S]*)\)\z/)
        arguments(combined[1]).each { |arg| read_reader(arg.strip) }
      elsif reader = expression.match(/\Anew\s+(?:[\w.]+\.)?(QueryString|Header|UrlSegment)ApiVersionReader\s*\(([\s\S]*)\)\z/)
        return if reader[1] == "UrlSegment"
        location = reader[1] == "Header" ? "header" : "query"
        if reader[2].blank?
          if location == "query"
            @readers << {location, "api-version"}
          else
            @unknown_reader = true
          end
        else
          arguments(reader[2]).each do |arg|
            if name = CSharpDecl.literal(arg)
              @readers << {location, name}
            else
              @unknown_reader = true
            end
          end
        end
      else
        @unknown_reader = true
      end
    end

    private def arguments(text)
      TopLevelSplit.split(text, ',', TopLevelSplit::Rules::CSHARP_PARAMS)
    end
  end
end
