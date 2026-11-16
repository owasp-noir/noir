require "../models/endpoint"
require "../utils/http_symbols"

module NoirAIContext::OutboundRequest
  extend self

  record Target, url : String?, method : String?, template : Bool = false

  # Only recognized HTTP APIs, with their URL as the first argument. A
  # variable-only URL, options-object request or computed call stays unresolved.
  CALL   = /(?<![\w.])(?:fetch|axios|(?:requests|httpx|axios|http|client|[A-Za-z_]\w*Client)\.(?:get|post|put|patch|delete|head|options|Get|Post)|[A-Za-z_]\w*\.(?:getForObject|postForObject|exchange)|(?:reqwest|ureq|surf)::(?:get|post|put|patch|delete))\s*\(/
  STRING = /\A(?:[rf]?(['"])([^'"\n\\]*)\1|`([^`\n\\]*)`)/
  NAME   = /\A[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*/
  METHOD = /\A,\s*\{\s*method\s*:\s*['"]([A-Za-z]+)['"]\s*\}\s*\)/

  def targets(sink : AIContextEntry) : Array(Target)
    source = sink.snippet || ""
    # Callee snippets include neighboring lines. Start at the actual call;
    # route-source sinks instead describe the whole handler.
    if sink.source == "callee" && (line = sink.line) && (start = source.index(/(?:\A| \| )#{line}:\s*/))
      source = source[start..]
    end
    source = source.gsub(/(?:\A| \| )\d+:\s*/, "\n").lstrip
    targets = [] of Target
    calls = code_mask(source).scan(CALL)
    if sink.source == "callee"
      line_end = source.index('\n') || source.size
      name = sink.name.split(' ', 2)[0]
      calls = calls.select { |call| call.begin(0) < line_end && call[0].starts_with?(name) }
    end
    calls.each do |match|
      targets << Target.new(nil, nil)
      rest = source[match.end(0)..].lstrip
      url, consumed, template = read_url(rest) || next
      tail = rest[consumed..].lstrip
      next unless tail.starts_with?(',') || tail.starts_with?(')')
      call = match[0].rstrip.rchop('(').strip
      verb = call.split(/[.:]/).last.downcase
      method = case verb
               when "get", "getforobject"                       then "GET"
               when "post", "postforobject"                     then "POST"
               when "put", "patch", "delete", "head", "options" then verb.upcase
               when "fetch"
                 # Only an unambiguous single-property options object. Nested
                 # fields, duplicate keys and spreads cannot set a known verb.
                 tail.starts_with?(')') ? "GET" : tail.match(METHOD).try(&.[1].upcase)
               end
      next if method && !::ALLOWED_HTTP_METHODS.includes?(method)
      targets.pop
      targets << Target.new(url, method, template)
    end
    targets.uniq
  end

  # Mask literals/comments for discovery; read arguments from the original.
  private def code_mask(source : String) : String
    chars = source.chars
    quote = ""
    comment = :none
    index = 0
    String.build do |io|
      while index < chars.size
        char = chars[index]
        pair = chars[index, Math.min(2, chars.size - index)].join
        triple = chars[index, Math.min(3, chars.size - index)].join
        if comment == :line
          comment = :none if char == '\n'
          io << (char == '\n' ? '\n' : ' ')
        elsif comment == :block
          if pair == "*/"
            comment = :none
            io << "  "
            index += 2
            next
          end
          io << ' '
        elsif !quote.empty?
          if char == '\\' && index + 1 < chars.size
            io << "  "
            index += 2
            next
          end
          if (quote.size == 3 && triple == quote) || (quote.size == 1 && char.to_s == quote)
            io << " " * quote.size
            index += quote.size
            quote = ""
            next
          end
          io << (char == '\n' ? '\n' : ' ')
        elsif char == '#' || pair == "//"
          comment = :line
          io << ' '
        elsif pair == "/*"
          comment = :block
          io << "  "
          index += 2
          next
        elsif char.in?('\'', '"', '`')
          quote = triple == "\"\"\"" || triple == "'''" ? triple : char.to_s
          io << " " * quote.size
          index += quote.size
          next
        else
          io << char
        end
        index += 1
      end
    end
  end

  # Read a small string expression, never evaluate repository code. A dynamic
  # component occupies one complete path segment; arbitrary suffix expressions
  # and unknown base paths are left unresolved rather than shortened to a URL.
  private def read_url(source : String) : {String, Int32, Bool}?
    rest = source
    parts = [] of String
    template = false
    loop do
      if literal = rest.match(STRING)
        text = literal[2]? || literal[3].to_s
        interpolation = literal[0].starts_with?('`') ? /\$\{[^{}]+\}/ : /\{[A-Za-z_]\w*\}/
        if literal[0].starts_with?('`') || literal[0].starts_with?('f')
          template ||= text.matches?(interpolation)
          text = text.gsub(interpolation, "{value}")
        end
        parts << text
        rest = rest[literal[0].size..].lstrip
      elsif name = rest.match(NAME)
        template = true
        parts << "{value}"
        rest = rest[name[0].size..].lstrip
      else
        return
      end
      break unless rest.starts_with?('+')
      rest = rest[1..].lstrip
    end
    url = parts.join
    return unless url.starts_with?('/') || url.starts_with?("http://") || url.starts_with?("https://")
    # Unknown values embedded in a literal segment or authority do not have
    # the one-segment semantics used by the route matcher.
    path = url.split('?', 2)[0].split('#', 2)[0]
    return if template && path.matches?(/[^\/]\{value\}|\{value\}[^\/]/)
    return if template && url.matches?(%r{\Ahttps?://[^/]*\{value\}})
    {url, source.size - rest.size, template}
  end
end
