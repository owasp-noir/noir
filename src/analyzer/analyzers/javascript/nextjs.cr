require "../../engines/javascript_engine"

module Analyzer::Javascript
  class Nextjs < JavascriptEngine
    HTTP_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    EXTENSIONS   = [".js", ".jsx", ".ts", ".tsx", ".mjs"]

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan(EXTENSIONS) do |path|
        if app_router_file?(path)
          analyze_app_router_file(path, result, mutex)
        elsif pages_router_file?(path)
          analyze_pages_router_file(path, result, mutex)
        else
          analyze_server_actions_file(path, result, mutex)
        end
      end

      result
    end

    private def app_router_file?(path : String) : Bool
      return false unless path.includes?("/app/")
      EXTENSIONS.any? { |ext| path.ends_with?("/route#{ext}") }
    end

    private def pages_router_file?(path : String) : Bool
      path.includes?("/pages/api/")
    end

    private def analyze_pages_router_file(path : String, result : Array(Endpoint), mutex : Mutex)
      idx = path.index("/pages/api/")
      return if idx.nil?

      relative = path[(idx + "/pages/api/".size)..-1]
      relative = strip_extension(relative)

      # Skip private folders/files (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      url = "/api/" + convert_segments(relative)
      url = normalize_url(url)

      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      methods = detect_pages_router_methods(content)

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(path, 1))

        extract_path_params(url, endpoint)
        extract_pages_router_params(content, endpoint)

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_app_router_file(path : String, result : Array(Endpoint), mutex : Mutex)
      idx = path.index("/app/")
      return if idx.nil?

      relative = path[(idx + "/app/".size)..-1]
      # Drop /route.ext
      EXTENSIONS.each do |ext|
        if relative.ends_with?("/route#{ext}")
          relative = relative[0..(relative.size - "/route#{ext}".size - 1)]
          break
        elsif relative == "route#{ext}"
          relative = ""
          break
        end
      end

      # Skip private folders (leading underscore)
      return if relative.split("/").any?(&.starts_with?("_"))

      # Strip route groups (parenthesized segments)
      segments = relative.split("/").reject { |seg| seg.empty? || (seg.starts_with?("(") && seg.ends_with?(")")) }
      converted = segments.map { |seg| convert_segment(seg) }

      url = "/" + converted.join("/")
      url = normalize_url(url)

      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      methods = extract_app_router_methods(content)
      return if methods.empty?

      methods.each do |method|
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(path, 1))

        extract_path_params(url, endpoint)
        extract_app_router_params(content, endpoint)

        mutex.synchronize { result << endpoint }
      end
    end

    private def analyze_server_actions_file(path : String, result : Array(Endpoint), mutex : Mutex)
      begin
        content = read_file_content(path)
      rescue e
        logger.debug "Error reading file #{path}: #{e.message}"
        return
      end

      # File must declare "use server" directive at the top
      return unless has_use_server_directive?(content)

      # Extract exported async functions
      content.scan(/export\s+async\s+function\s+(\w+)\s*\(([^)]*)\)/) do |match|
        action_name = match[1]
        args = match[2]

        url = "/" + action_name
        endpoint = Endpoint.new(url, "POST")
        endpoint.details = Details.new(PathInfo.new(path, 1))

        extract_server_action_params(args, content, action_name, endpoint)

        mutex.synchronize { result << endpoint }
      end
    end

    private def detect_pages_router_methods(content : String) : Array(String)
      # If named HTTP method exports exist, use them; otherwise default handler covers all.
      explicit = [] of String
      HTTP_METHODS.each do |m|
        if content.match(/export\s+(?:async\s+)?function\s+#{m}\b/) ||
           content.match(/export\s+const\s+#{m}\s*=/)
          explicit << m
        end
      end

      return explicit unless explicit.empty?

      # Heuristic: look for req.method checks to infer declared methods.
      inferred = [] of String
      content.scan(/req\.method\s*===?\s*['"]([A-Z]+)['"]/) do |m|
        method = m[1]
        inferred << method if HTTP_METHODS.includes?(method) && !inferred.includes?(method)
      end

      return inferred unless inferred.empty?

      # Default-export handler — applies to ALL methods.
      ["GET", "POST", "PUT", "DELETE", "PATCH"]
    end

    private def extract_app_router_methods(content : String) : Array(String)
      methods = [] of String
      HTTP_METHODS.each do |m|
        if content.match(/export\s+(?:async\s+)?function\s+#{m}\b/) ||
           content.match(/export\s+const\s+#{m}\s*=/) ||
           content.match(/export\s+\{[^}]*\b#{m}\b[^}]*\}/)
          methods << m
        end
      end
      methods
    end

    private def extract_pages_router_params(content : String, endpoint : Endpoint)
      # req.query.X and req.query["X"]
      content.scan(/req\.query\.(\w+)/) do |m|
        add_param(endpoint, m[1], "query")
      end
      content.scan(/req\.query\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # Destructured query: const { foo, bar } = req.query
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.query/) do |m|
        m[1].split(",").each do |raw|
          name = raw.strip.split(/[:=\s]/).first
          add_param(endpoint, name, "query") unless name.empty?
        end
      end

      # req.body.X and req.body["X"]
      content.scan(/req\.body\.(\w+)/) do |m|
        add_param(endpoint, m[1], "body")
      end
      content.scan(/req\.body\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "body")
      end

      # Destructured body: const { foo, bar } = req.body
      content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*req\.body/) do |m|
        m[1].split(",").each do |raw|
          name = raw.strip.split(/[:=\s]/).first
          add_param(endpoint, name, "body") unless name.empty?
        end
      end

      # req.headers["x-token"] or req.headers.foo
      content.scan(/req\.headers\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "header")
      end
      content.scan(/req\.headers\.(\w+)/) do |m|
        add_param(endpoint, m[1], "header")
      end

      # req.cookies["session"] or req.cookies.name
      content.scan(/req\.cookies\[['"]([^'"]+)['"]\]/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
      content.scan(/req\.cookies\.(\w+)/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
    end

    private def extract_app_router_params(content : String, endpoint : Endpoint)
      # request.nextUrl.searchParams.get("X") or searchParams.get("X")
      content.scan(/(?:searchParams|nextUrl\.searchParams)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "query")
      end

      # await request.json() — body present; try to extract field access patterns
      if content.includes?("request.json()") || content.includes?(".json()")
        content.scan(/(?:const|let|var)\s*\{\s*([^}]+?)\s*\}\s*=\s*await\s+(?:request|req)\.json\s*\(\s*\)/) do |m|
          m[1].split(",").each do |raw|
            name = raw.strip.split(/[:=\s]/).first
            add_param(endpoint, name, "json") unless name.empty?
          end
        end
      end

      # formData: const formData = await request.formData(); formData.get("name")
      if content.includes?("formData()")
        content.scan(/formData\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
          add_param(endpoint, m[1], "form")
        end
      end

      # request.headers.get("x-token")
      content.scan(/(?:request|req)\.headers\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "header")
      end

      # cookies().get("session") from next/headers
      content.scan(/cookies\(\)\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
        add_param(endpoint, m[1], "cookie")
      end
    end

    private def extract_server_action_params(args : String, content : String, action_name : String, endpoint : Endpoint)
      # Detect FormData args: (formData: FormData) → look up formData.get("x") calls
      if args.match(/formData\s*:\s*FormData/) || args.match(/\bformData\b/i)
        content.scan(/formData\.get\s*\(\s*['"]([^'"]+)['"]\s*\)/) do |m|
          add_param(endpoint, m[1], "form")
        end
      end

      # Plain positional arguments become body params
      args.split(",").each do |arg|
        arg = arg.strip
        next if arg.empty?
        # Strip type annotations and default values
        name = arg.split(":").first.strip.split("=").first.strip
        next if name.empty?
        next if name == "formData"
        # Handle destructuring: { email, name }: SomeType
        if name.starts_with?("{") && name.ends_with?("}")
          inner = name[1..-2]
          inner.split(",").each do |piece|
            pname = piece.strip.split(/[:=\s]/).first
            add_param(endpoint, pname, "body") unless pname.empty?
          end
        else
          add_param(endpoint, name, "body")
        end
      end
    end

    private def extract_path_params(url : String, endpoint : Endpoint)
      url.scan(/\{(\w+)\}/) do |m|
        add_param(endpoint, m[1], "path")
      end
    end

    private def add_param(endpoint : Endpoint, name : String, type : String)
      return if name.empty?
      return if endpoint.params.any? { |p| p.name == name && p.param_type == type }
      endpoint.push_param(Param.new(name, "", type))
    end

    private def strip_extension(path : String) : String
      EXTENSIONS.each do |ext|
        return path[0..(path.size - ext.size - 1)] if path.ends_with?(ext)
      end
      path
    end

    private def convert_segments(relative : String) : String
      segments = relative.split("/").reject(&.empty?)
      segments.map { |seg| convert_segment(seg) }.join("/")
    end

    private def convert_segment(seg : String) : String
      # Optional catch-all: [[...slug]]
      if m = seg.match(/^\[\[\.\.\.(\w+)\]\]$/)
        return "{#{m[1]}}"
      end
      # Catch-all: [...slug]
      if m = seg.match(/^\[\.\.\.(\w+)\]$/)
        return "{#{m[1]}}"
      end
      # Dynamic: [id]
      if m = seg.match(/^\[(\w+)\]$/)
        return "{#{m[1]}}"
      end
      seg
    end

    private def has_use_server_directive?(content : String) : Bool
      stripped = content.lstrip
      # Skip leading comments
      while stripped.starts_with?("//") || stripped.starts_with?("/*")
        if stripped.starts_with?("//")
          newline = stripped.index('\n')
          return false if newline.nil?
          stripped = stripped[(newline + 1)..].lstrip
        else
          close = stripped.index("*/")
          return false if close.nil?
          stripped = stripped[(close + 2)..].lstrip
        end
      end
      stripped.starts_with?(%("use server")) || stripped.starts_with?(%('use server')) ||
        stripped.starts_with?("`use server`")
    end

    private def normalize_url(url : String) : String
      url = url.gsub(/\/+/, "/")
      url = url.sub(/\/index$/, "")
      url = url.sub(/\/+$/, "") unless url == "/"
      url = "/" if url.empty?
      url
    end
  end
end
