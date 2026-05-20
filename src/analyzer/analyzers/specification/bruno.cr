require "../../../models/analyzer"

module Analyzer::Specification
  class Bruno < Analyzer
    HTTP_METHODS = {"get", "post", "put", "patch", "delete", "head", "options"}

    def analyze
      locator = CodeLocator.instance
      bruno_files = locator.all("bruno-bru")

      bruno_files.each do |bruno_file|
        next unless File.exists?(bruno_file)
        begin
          content = read_file_content(bruno_file)
          details = Details.new(PathInfo.new(bruno_file))
          process_bru(content, details)
        rescue e
          @logger.debug "Exception processing #{bruno_file}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private record Block, name : String, body : String

    # The `.bru` format is `name { body }` blocks with no nesting beyond
    # body content. We walk char-by-char and brace-count so that
    # `body:json { { "a": 1 } }` (where the body itself is JSON) works.
    private def parse_blocks(content : String) : Array(Block)
      blocks = [] of Block
      chars = content.chars
      size = chars.size
      i = 0
      while i < size
        while i < size && chars[i].whitespace?
          i += 1
        end
        break if i >= size

        name_start = i
        while i < size && chars[i] != '{' && chars[i] != '\n'
          i += 1
        end

        if i >= size || chars[i] != '{'
          # Not a block header on this line; skip to newline and retry.
          while i < size && chars[i] != '\n'
            i += 1
          end
          next
        end

        name = chars[name_start...i].join.strip
        i += 1 # consume '{'

        depth = 1
        body_start = i
        while i < size && depth > 0
          case chars[i]
          when '{'
            depth += 1
          when '}'
            depth -= 1
          end
          i += 1
        end

        body_end = depth == 0 ? i - 1 : i
        body = chars[body_start...body_end].join
        blocks << Block.new(name, body) unless name.empty?
      end
      blocks
    end

    private def parse_kv_lines(body : String) : Array(Tuple(String, String))
      pairs = [] of Tuple(String, String)
      body.each_line do |line|
        stripped = line.strip
        next if stripped.empty?
        next if stripped.starts_with?('~') # disabled entry
        idx = stripped.index(':')
        next if idx.nil?
        key = stripped[0...idx].strip
        value = stripped[(idx + 1)..].strip
        next if key.empty?
        pairs << {key, value}
      end
      pairs
    end

    private def process_bru(content : String, details)
      blocks = parse_blocks(content)

      method = nil
      url = nil
      params = [] of Param

      blocks.each do |block|
        name = block.name.downcase
        case name
        when "meta"
          # Metadata only; no endpoint signal.
        when "get", "post", "put", "patch", "delete", "head", "options"
          method = name.upcase
          parse_kv_lines(block.body).each do |k, v|
            url = v if k.downcase == "url"
          end
        when "query", "params:query"
          parse_kv_lines(block.body).each do |k, v|
            params << Param.new(k, v, "query")
          end
        when "params:path"
          parse_kv_lines(block.body).each do |k, v|
            params << Param.new(k, v, "path")
          end
        when "headers"
          parse_kv_lines(block.body).each do |k, v|
            next if k.downcase == "content-type"
            params << Param.new(k, v, "header")
          end
        when "body:json"
          extract_json_body(block.body).each { |p| params << p }
        when "body:form-urlencoded"
          parse_kv_lines(block.body).each do |k, v|
            params << Param.new(k, v, "form")
          end
        when "body:multipart-form"
          parse_kv_lines(block.body).each do |k, v|
            params << Param.new(k, v, "form")
          end
        end
      end

      resolved_method = method
      resolved_url = url
      return if resolved_method.nil? || resolved_url.nil?

      url_path = extract_path_from_url(resolved_url)
      return if url_path.empty?

      @result << Endpoint.new(url_path, resolved_method, params, details)
    rescue e
      @logger.debug "Exception processing .bru block"
      @logger.debug_sub e
    end

    private def extract_json_body(raw : String) : Array(Param)
      params = [] of Param
      stripped = raw.strip
      return params if stripped.empty?
      begin
        parsed = JSON.parse(stripped)
        if hash = parsed.as_h?
          hash.each do |k, v|
            params << Param.new(k, v.to_s, "json")
          end
        end
      rescue
        # Non-JSON or templated body (e.g. {{var}}) — skip silently.
      end
      params
    end

    private def extract_path_from_url(url_string : String) : String
      stripped = url_string.strip
      return "" if stripped.empty?

      # Drop query string; structured params live in the `query` block.
      q_idx = stripped.index('?')
      stripped = stripped[0...q_idx] if q_idx

      if stripped =~ /^https?:\/\//i
        rest = stripped.sub(/^https?:\/\//i, "")
        slash_idx = rest.index('/')
        if slash_idx
          path = rest[slash_idx..]
          return path.empty? ? "/" : path
        end
        return "/"
      end

      stripped.starts_with?('/') ? stripped : "/#{stripped}"
    end
  end
end
