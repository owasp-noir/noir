require "../../engines/scala_engine"

module Analyzer::Scala
  class Tapir < ScalaEngine
    HTTP_METHODS = %w[get post put delete patch head options connect trace]

    BASE_ENDPOINT_RE = /(?<![.\w])(?:[A-Za-z_]\w*[Ee]ndpoint|endpoint|infallibleEndpoint)\b/

    # Type token allows one level of nested brackets (e.g. Option[String], List[User]).
    TYPE_PATTERN = "(?:[^\\[\\]]|\\[[^\\[\\]]*\\])+"

    IN_TOKEN_RE = Regex.new(
      "\"(?<literal>[^\"]+)\"" \
      "|path\\[(?<path_type>#{TYPE_PATTERN})\\](?:\\s*\\(\\s*\"(?<path_name>[^\"]+)\"\\s*\\))?" \
      "|query\\[(?<query_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<query_name>[^\"]+)\"\\s*\\)" \
      "|queries\\[(?<queries_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<queries_name>[^\"]+)\"\\s*\\)" \
      "|header\\[(?<header_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<header_name>[^\"]+)\"\\s*\\)" \
      "|header\\s*\\(\\s*\"(?<header_name2>[^\"]+)\"" \
      "|cookie\\[(?<cookie_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<cookie_name>[^\"]+)\"\\s*\\)" \
      "|(?<body>jsonBody|xmlBody|stringBody|plainBody|binaryBody|byteArrayBody|byteBufferBody|formBody|multipartBody|rawBinaryBody|fileBody)(?:\\[(?<body_type>#{TYPE_PATTERN})\\])?"
    )

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content)
    end

    private def extract_routes_from_content(path : String, content : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = content.split('\n')
      consumed_until = -1

      lines.each_with_index do |_, index|
        next if index <= consumed_until
        code = scala_code_line(lines[index])
        next unless match = code.match(BASE_ENDPOINT_RE)
        col = match.begin || 0
        chain_text, last_line = collect_chain(lines, index, col)
        consumed_until = last_line

        endpoint = parse_chain(chain_text, path, index + 1)
        endpoints << endpoint if endpoint
      end

      endpoints
    end

    private def collect_chain(lines : Array(String), start : Int32, col : Int32) : Tuple(String, Int32)
      head = scala_code_line(lines[start])
      first = col < head.size ? head[col..] : ""
      parts = [first]
      idx = start + 1
      while idx < lines.size
        code = scala_code_line(lines[idx])
        if code.lstrip.starts_with?(".")
          parts << code
          idx += 1
        else
          break
        end
      end
      {parts.join("\n"), idx - 1}
    end

    private def parse_chain(chain : String, path : String, line_no : Int32) : Endpoint?
      method = detect_method(chain)
      return unless method

      endpoint = create_endpoint("/", method.upcase, path, line_no)
      segments = [] of String

      extract_in_blocks(chain).each do |args|
        process_in_args(args, endpoint, segments)
      end

      endpoint.url = segments.empty? ? "/" : "/" + segments.join("/")
      endpoint
    end

    private def detect_method(chain : String) : String?
      HTTP_METHODS.each do |m|
        return m if chain.matches?(/\.#{m}\b/)
      end

      if mm = chain.match(/\.method\s*\(\s*Method\.([A-Z]+)\s*\)/)
        candidate = mm[1].downcase
        return candidate if HTTP_METHODS.includes?(candidate)
      end

      nil
    end

    private def extract_in_blocks(chain : String) : Array(String)
      blocks = [] of String
      i = 0
      while i < chain.size
        slice = chain[i..]
        if slice.starts_with?(".in(") || slice.starts_with?(".securityIn(")
          open_paren = chain.index('(', i)
          if open_paren && (result = balanced_paren_content(chain, open_paren))
            blocks << result[0]
            i = result[1] + 1
            next
          end
        end
        i += 1
      end
      blocks
    end

    private def balanced_paren_content(s : String, open_idx : Int32) : Tuple(String, Int32)?
      depth = 0
      i = open_idx
      content_start = open_idx + 1
      while i < s.size
        c = s[i]
        if c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return {s[content_start...i], i} if depth == 0
        end
        i += 1
      end
      nil
    end

    private def process_in_args(args : String, endpoint : Endpoint, segments : Array(String))
      args.scan(IN_TOKEN_RE) do |m|
        if literal = m["literal"]?
          literal.split('/').reject(&.empty?).each { |seg| segments << seg }
        elsif m["path_type"]?
          name = m["path_name"]? || default_path_name(segments)
          segments << "{#{name}}"
          add_param(endpoint, name, "", "path")
        elsif q = m["query_name"]?
          add_param(endpoint, q, m["query_type"]? || "", "query")
        elsif q = m["queries_name"]?
          add_param(endpoint, q, m["queries_type"]? || "", "query")
        elsif h = m["header_name"]?
          add_param(endpoint, h, m["header_type"]? || "", "header")
        elsif h = m["header_name2"]?
          add_param(endpoint, h, "", "header")
        elsif c = m["cookie_name"]?
          add_param(endpoint, c, m["cookie_type"]? || "", "cookie")
        elsif body = m["body"]?
          inner = m["body_type"]? || ""
          param_type = case body
                       when "jsonBody"      then "json"
                       when "xmlBody"       then "xml"
                       when "formBody"      then "form"
                       when "multipartBody" then "form"
                       else
                         "body"
                       end
          add_param(endpoint, "body", inner, param_type)
        end
      end
    end

    private def add_param(endpoint : Endpoint, name : String, type_value : String, param_type : String)
      existing = endpoint.params.find { |p| p.name == name && p.param_type == param_type }
      return if existing

      endpoint.push_param(Param.new(name, type_value, param_type))
    end

    private def default_path_name(segments : Array(String)) : String
      anon_count = segments.count(&.starts_with?("{anon"))
      anon_count == 0 ? "anon" : "anon#{anon_count + 1}"
    end

    private def create_endpoint(url : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param
      Endpoint.new(url, method, params, details)
    end
  end
end
