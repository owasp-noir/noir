require "../../../models/analyzer"
require "../../../utils/utils.cr"

module Analyzer::Asp
  # Classic ASP (VBScript) attack surface.
  #
  # Classic ASP has no route table: an `.asp` file's path under the web
  # root *is* its URL, the same shape as plain PHP or JSP. The work is
  # therefore (a) deciding which `.asp` files are actually requestable
  # and (b) recovering the request keys the page reads.
  #
  # `global.asa` and `.inc` are never served (IIS refuses the former and
  # does not map the latter to the ASP engine), so only `.asp` is walked.
  class Classic < Analyzer
    # IIS-specific roots only. Generic names like `public/` are
    # deliberately absent — they collide with build output, the false
    # positive `FileHelper` documents.
    WEBROOT_MARKERS = ["wwwroot/", "inetpub/"]

    # IIS default documents: also reachable as the bare directory URL.
    DIRECTORY_INDEXES = Set{"default.asp", "index.asp"}

    # `<!-- #include file="..." -->`. Most real code puts a space after
    # `<!--`, and `virtual=` is web-root-absolute while `file=` is
    # relative to the including file.
    INCLUDE_RE = /<!--\s*#include\s+(file|virtual)\s*=\s*["']([^"']+)["']\s*-->/i

    # Server code lives in `<% %>` / `<%= %>` or a `runat="server"`
    # script block; `<%@ %>` is a page directive, not code.
    SERVER_SCRIPT_RE = /(<script\b[^>]*\brunat\s*=\s*["']?server["']?[^>]*>)([\s\S]*?)(<\/script>)/i

    # Intrinsic collection reads. The name must be a double-quoted
    # literal closed immediately by `)` — `Request("prefix" & id)` is a
    # runtime-built key, and capturing `prefix` from it would be wrong.
    # Whitespace before `(` is not optional decoration: it appears in
    # over half of real form reads (`Request.Form ("x")`).
    REQUEST_RE = /\brequest\s*(?:\.\s*(form|querystring|cookies|servervariables)\s*)?\(\s*"([^"]*)"\s*\)/i

    # Framework wrappers that merge the collections. Without these a real
    # CMS loses most of its surface: QuickerSite routes nearly every
    # dynamic param through aspLite's `getRequest`.
    WRAPPER_RE = /\b(?:getRequest|Easp\s*\.\s*[GPR])\s*\(\s*"([^"]*)"\s*\)/i

    BINARY_READ_RE = /\brequest\s*\.\s*(?:binaryread|totalbytes)\b/i

    # A form only makes *this* page a POST target when it submits back to
    # itself. Treating any `<form>` as a self-post gave every page hosting
    # a search or login box that posts to a dedicated handler a phantom
    # POST endpoint.
    FORM_TAG_RE    = /<form\b([^>]*)>/i
    FORM_ACTION_RE = /\baction\s*=\s*["']?([^"'\s>]*)/i

    # Only an equality test is evidence the page handles POST; `<>` is the
    # opposite guard.
    POST_METHOD_RE  = /request\s*\.\s*servervariables\s*\(\s*"request_method"\s*\)\s*=\s*"post"/i
    CONTINUATION_RE = /_[ \t]*\r?\n/

    # Fragments that are included rather than requested. The include
    # graph below is the real filter; these catch the conventional cases
    # it can miss (a fragment nobody includes statically).
    INCLUDE_DIR_RE  = /\/(?:includes?|inc)\//i
    INCLUDE_NAME_RE = /\A(?:lib|partial)\./i

    def analyze
      asp_files = get_files_by_extension(".asp").reject { |path| File.directory?(path) }
      return @result if asp_files.empty?

      # Pass 1: every file reachable only via `#include` is a fragment,
      # not a route. QuickerSite alone would otherwise contribute 116
      # phantom endpoints, and the most-included fragments sit beside
      # genuine pages rather than in an `includes/` directory, so a
      # name-based rule cannot substitute for the graph.
      included = collect_include_targets(asp_files + get_files_by_extension(".inc") + get_files_by_extension(".asa"))

      routable = asp_files.reject { |path| fragment?(path, included) }

      parallel_analyze(routable) do |path|
        analyze_page(path)
      end

      @result
    end

    private def collect_include_targets(files : Array(String)) : Set(String)
      targets = Set(String).new

      files.each do |path|
        next if File.directory?(path)

        content = read_file_content(path)
        next unless content.includes?("#include")

        directory = File.dirname(path)
        base = configured_base_for(path)

        content.scan(INCLUDE_RE) do |match|
          reference = match[2].gsub('\\', '/').strip
          next if reference.empty?

          resolved =
            if match[1].downcase == "virtual"
              File.join(base, reference.lchop('/'))
            else
              File.join(directory, reference)
            end

          targets << File.expand_path(resolved)
        end
      rescue e
        logger.debug "Error collecting includes from #{path}: #{e}"
      end

      targets
    end

    private def fragment?(path : String, included : Set(String)) : Bool
      # An IIS default document is served whether or not something also
      # includes it — QuickerSite's `index.asp` is a one-line include of
      # `default.asp`, and both answer requests.
      return false if DIRECTORY_INDEXES.includes?(File.basename(path).downcase)

      return true if included.includes?(File.expand_path(path))

      normalized = path.gsub(File::SEPARATOR, "/")
      return true if normalized.matches?(INCLUDE_DIR_RE)

      File.basename(path).matches?(INCLUDE_NAME_RE)
    end

    private def analyze_page(path : String)
      raw = read_file_content(path)
      code = strip_vbscript_comments(server_code(raw)).gsub(CONTINUATION_RE, " ")

      query = [] of Param
      body = [] of Param
      cookies = [] of Param
      headers = [] of Param
      ambiguous = [] of String
      saw_form_read = false

      code.scan(REQUEST_RE) do |match|
        name = match[2]
        next if name.empty?

        case match[1]?.try(&.downcase)
        when "querystring" then query << Param.new(name, "", "query")
        when "form"
          body << Param.new(name, "", "form")
          saw_form_read = true
        when "cookies" then cookies << Param.new(name, "", "cookie")
        when "servervariables"
          header = server_variable_header(name)
          headers << Param.new(header, "", "header") if header
        else
          # Bare `Request("x")` searches QueryString, then Form, then
          # Cookies — it is genuinely both, so report it as both rather
          # than guessing.
          ambiguous << name
        end
      end

      code.scan(WRAPPER_RE) do |match|
        ambiguous << match[1] unless match[1].empty?
      end

      saw_form_read ||= code.matches?(BINARY_READ_RE)

      ambiguous.each do |name|
        query << Param.new(name, "", "query")
        body << Param.new(name, "", "form")
      end

      details = Details.new(PathInfo.new(path))
      urls = request_paths(path)

      get_params = unique_params(query + cookies + headers)
      urls.each { |url| @result << Endpoint.new(url, "GET", get_params, details) }

      # A page is a POST target when it reads the form collection, when
      # a bare `Request(...)` read could resolve to it, or when it posts
      # to itself — the dominant Classic ASP shape, where one URL both
      # renders the form on GET and handles it on POST.
      posts = saw_form_read || ambiguous.present? || code.matches?(POST_METHOD_RE) || self_posting_form?(raw, path)
      return unless posts

      post_params = unique_params(body + cookies + headers)
      urls.each { |url| @result << Endpoint.new(url, "POST", post_params, details) }
    end

    # Only `HTTP_*` server variables carry inbound request data; the rest
    # (REMOTE_ADDR, SCRIPT_NAME, ...) are server state.
    private def server_variable_header(name : String) : String?
      return unless name.downcase.starts_with?("http_")

      header = name[5..].gsub("_", "-").downcase
      header.empty? ? nil : header
    end

    # `default.asp` / `index.asp` answer the bare directory URL too.
    private def request_paths(path : String) : Array(String)
      url = web_root_path(path, WEBROOT_MARKERS)
      return [url] unless DIRECTORY_INDEXES.includes?(File.basename(path).downcase)

      directory = url.rpartition('/').first
      directory = "" if directory.empty?
      [url, "#{directory}/"]
    end

    # True when a `<form>` on the page submits back to the page itself,
    # the dominant Classic ASP shape where one URL renders on GET and
    # handles the submission on POST.
    private def self_posting_form?(raw : String, path : String) : Bool
      basename = File.basename(path).downcase

      raw.scan(FORM_TAG_RE) do |match|
        action = match[1].match(FORM_ACTION_RE)
        # No action attribute at all posts to the current URL.
        return true unless action

        target = action[1].strip
        return true if target.empty? || target == "#"

        target = target.split('?').first.split('#').first.split('/').last.downcase
        return true if target.empty? || target == basename
      end

      false
    end

    # Blank everything that is not server-side code, keeping newlines.
    #
    # ASP interleaves code and HTML freely — a single physical line can
    # close a VBScript block, emit markup, open a loop and end with two
    # includes — so this cannot be line-oriented, and scanning the raw
    # file would let client-side JavaScript register as request reads.
    private def server_code(content : String) : String
      return content unless content.includes?("<%") || content.matches?(SERVER_SCRIPT_RE)

      chars = content.chars
      size = chars.size
      keep = Array(Bool).new(size, false)

      index = 0
      while index < size - 1
        unless chars[index] == '<' && chars[index + 1] == '%'
          index += 1
          next
        end

        body_start = index + 2
        # `<%@ ... %>` is a page directive (language, codepage), not code.
        directive = body_start < size && chars[body_start] == '@'
        # `<%=` is Response.Write shorthand; its body is still VBScript.
        body_start += 1 if body_start < size && chars[body_start] == '='

        close = body_start
        while close < size - 1 && !(chars[close] == '%' && chars[close + 1] == '>')
          close += 1
        end
        terminated = close < size - 1
        stop = terminated ? close : size

        (body_start...stop).each { |position| keep[position] = true } unless directive
        index = terminated ? close + 2 : size
      end

      content.scan(SERVER_SCRIPT_RE) do |match|
        start = match.begin(2)
        stop = match.end(2)
        (start...stop).each { |position| keep[position] = true } if start && stop
      end

      String.build do |io|
        chars.each_with_index do |char, position|
          io << (char == '\n' || keep[position] ? char : ' ')
        end
      end
    end

    # Blank `'` comments. VBScript escapes a quote by doubling it and has
    # no backslash escape, so an apostrophe inside a string literal (very
    # common in emitted JavaScript) is not a comment — the scan has to be
    # string-aware or it truncates live code.
    private def strip_vbscript_comments(content : String) : String
      return content unless content.includes?('\'')

      chars = content.chars
      in_string = false
      in_comment = false

      String.build do |io|
        chars.each do |char|
          if char == '\n'
            in_comment = false
            in_string = false
            io << char
            next
          end

          if in_comment
            io << ' '
            next
          end

          if in_string
            in_string = false if char == '"'
            io << char
            next
          end

          case char
          when '"'
            in_string = true
            io << char
          when '\''
            in_comment = true
            io << ' '
          else
            io << char
          end
        end
      end
    end
  end
end
