require "../../../models/analyzer"
require "../../../utils/utils.cr"

module Analyzer::Aspnet
  # ASP.NET WebForms attack surface.
  #
  # WebForms is file-path routed: an `.aspx` page's location under the web
  # root *is* its URL. The parameters, however, mostly do not live in the
  # page — they live in its code-behind and, more often, in the `.ascx`
  # user controls the page registers. Across the validation corpus only
  # ~19% of literal request reads sit in page code-behind and 54% sit in
  # user controls, so a page-only scan would miss most of the surface.
  # Control reads are therefore attributed to the pages that register
  # them.
  class WebForms < Analyzer
    # Requestable handlers. `.ascx` (user control) and `.master` (master
    # page) are composed into pages and are blocked by the default IIS
    # handler mapping, so they are sources of params but never routes.
    PAGE_EXTENSIONS = [".aspx", ".ashx", ".asmx"]

    # `Global.asax` marks the application root, and unlike CFML's
    # `Application.cfc` there is at most one per web app (verified across
    # the corpus: 1 for kartris, 1 for DNN at `DNN Platform/Website/`,
    # 0 for the two module-style repos), which makes it a trustworthy
    # anchor rather than a guess.
    GLOBAL_ASAX      = "global.asax"
    WEBROOT_MARKERS  = ["wwwroot/"]
    DIRECTORY_INDEX  = "default.aspx"
    DESIGNER_FILE_RE = /\.designer\.(?:cs|vb)\z/i

    # Directives span multiple physical lines in real projects, so the
    # whole `<%@ ... %>` block is captured rather than the first line.
    PAGE_DIRECTIVE_RE     = /<%@\s*(?:Page|Control|Master|WebHandler|WebService)\b([\s\S]*?)%>/i
    REGISTER_DIRECTIVE_RE = /<%@\s*Register\b([\s\S]*?)%>/i
    DIRECTIVE_ATTR_RE     = /([\w:.-]+)\s*=\s*"([^"]*)"/

    # Collection reads, in both indexer syntaxes. In every pattern below
    # the closing delimiter must follow the literal immediately:
    # `Request("laauth-" & TabModuleId)` builds its key at runtime, and
    # capturing `laauth-` from it would invent 216 bogus params.
    #
    # `QueryString` / `Form` / `ServerVariables` name nothing but an HTTP
    # request, so any receiver is accepted. That is what catches aliased
    # locals: kartris's `Image.ashx` assigns
    # `Dim req As HttpRequest = context.Request` and then does ten reads
    # through `req`, which a `Request`-anchored pattern would all miss.
    ALIASED_COLLECTION_RE = /\b\w+\s*\.\s*(QueryString|Form|ServerVariables)\s*[\(\[]\s*"([^"]*)"\s*[\)\]]/i

    # `Params` / `Cookies` / `Headers` are ordinary member names — mail
    # messages, HTTP clients and parsers all expose them — so these must
    # be anchored to `Request`. `\bRequest\.` still covers every receiver
    # chain (`this.`, `context.`, `HttpContext.Current.`).
    REQUEST_COLLECTION_RE = /\bRequest\s*\.\s*(QueryString|Form|Params|Cookies|Headers|ServerVariables)\s*[\(\[]\s*"([^"]*)"\s*[\)\]]/i

    BARE_REQUEST_RE = /\bRequest\s*[\(\[]\s*"([^"]*)"\s*[\)\]]/i

    # `[WebMethod]` / `<WebMethod()>` on an `.asmx` service maps to
    # `POST /Service.asmx/MethodName`.
    WEBMETHOD_ATTR_RE = /(?:\[WebMethod[^\]]*\]|<WebMethod[^>]*>)/i
    VB_SIGNATURE_RE   = /\b(?:Public|Friend)\s+(?:(?:Overrides|Shared|Overloads|NotOverridable)\s+)*(?:Function|Sub)\s+(\w+)\s*\(([^)]*)\)/
    CS_SIGNATURE_RE   = /\b(?:public|internal)\s+(?:(?:static|virtual|override|async)\s+)*[\w<>\[\],.\s]+?\s+(\w+)\s*\(([^)]*)\)/
    WEBMETHOD_WINDOW  = 400

    # WebForms postback plumbing, not user-facing parameters.
    FRAMEWORK_FIELDS = Set{
      "__viewstate", "__viewstategenerator", "__viewstateencrypted",
      "__eventtarget", "__eventargument", "__eventvalidation",
      "__lastfocus", "__previouspage", "__asyncpost",
      "__scrollpositionx", "__scrollpositiony",
    }

    # Class declarations, used only to resolve services whose code lives
    # away from the handler file.
    CLASS_DEFINITION_RE = /(?:^|\s)(?:Partial\s+|partial\s+)?(?:Public\s+|Friend\s+|public\s+|internal\s+)?(?:Class|class)\s+(\w+)/

    SERVICE_EXTENSIONS = [".asmx", ".ashx"]

    @webroots : Array(String)? = nil
    @file_index : Hash(String, String)? = nil
    @class_index : Hash(String, String)? = nil

    def analyze
      pages = PAGE_EXTENSIONS.flat_map { |extension| get_files_by_extension(extension) }
        .uniq!
        .reject { |path| File.directory?(path) }
      return @result if pages.empty?

      # These lookups walk the whole file map; resolve them once up front
      # so worker fibers never race to build them.
      webroots
      file_index
      build_class_index if class_index_needed?(pages)

      parallel_analyze(pages) do |path|
        analyze_page(path)
      end

      @result
    end

    private def analyze_page(path : String)
      url = page_url(path)
      details = Details.new(PathInfo.new(path))
      sources = collect_sources(path)

      if File.extname(path).downcase == ".asmx"
        emit_web_methods(url, sources, details)
        return
      end

      buckets = ParamBuckets.new
      sources.each { |source| scan_source(source, buckets) }

      urls = [url]
      urls << directory_url(url) if File.basename(path).downcase == DIRECTORY_INDEX

      # A WebForms page with a server-side form answers both verbs by
      # construction — the framework posts back to the page's own URL —
      # and `IsPostBack` proves both paths share one handler rather than
      # distinguishing them.
      urls.each do |page_url|
        @result << Endpoint.new(page_url, "GET", unique_params(buckets.query_side), details)
        @result << Endpoint.new(page_url, "POST", unique_params(buckets.body_side), details)
      end
    end

    # A page's params come from its own inline code, its code-behind, its
    # master page and every user control it registers (transitively).
    private def collect_sources(path : String) : Array(String)
      sources = [] of String
      visited = Set(String).new
      queue = [path]

      while current = queue.shift?
        begin
          key = File.expand_path(current).downcase
          next unless visited.add?(key)
          next if current.matches?(DESIGNER_FILE_RE)

          sources << current

          if code_behind = code_behind_for(current)
            queue << code_behind
          end

          # Only markup carries directives; code-behind does not.
          next unless markup?(current)

          content = read_file_content(current)
          composed_references(current, content).each { |reference| queue << reference }
        rescue e
          logger.debug "Error resolving sources for #{current}: #{e}"
        end
      end

      sources
    end

    # `Src="~/Controls/Foo.ascx"` on a Register directive, plus the
    # page's `MasterPageFile`.
    private def composed_references(path : String, content : String) : Array(String)
      references = [] of String

      content.scan(REGISTER_DIRECTIVE_RE) do |match|
        source = directive_attributes(match[1])["src"]?
        next if source.nil? || source.empty?

        if resolved = resolve_reference(path, source)
          references << resolved
        end
      end

      content.scan(PAGE_DIRECTIVE_RE) do |match|
        master = directive_attributes(match[1])["masterpagefile"]?
        next if master.nil? || master.empty?

        if resolved = resolve_reference(path, master)
          references << resolved
        end
      end

      references
    end

    # Prefer the directive, fall back to a case-insensitive sibling
    # lookup. Both are advisory: 11% of pages in the corpus name their
    # code-behind with different casing than the file on disk, 2.5% carry
    # no directive at all, and one names a file that does not exist. A
    # page with no resolvable code-behind is still a route.
    private def code_behind_for(path : String) : String?
      return unless markup?(path)

      content = read_file_content(path)
      if match = content.match(PAGE_DIRECTIVE_RE)
        attributes = directive_attributes(match[1])
        reference = attributes["codebehind"]? || attributes["codefile"]?
        if reference && !reference.empty?
          if resolved = resolve_reference(path, reference)
            return resolved
          end
        end
      end

      {".cs", ".vb"}.each do |extension|
        if found = lookup_file("#{File.expand_path(path)}#{extension}")
          return found
        end
      end

      # Services often name only the type and keep the implementation in
      # `App_Code/` under an unrelated filename — kartris ships
      # `KartrisQBService.asmx` (`Class="KartrisQBService"`, no
      # CodeBehind) whose code is `App_Code/KartrisQBService.vb`, and
      # `kartrisServices.asmx` whose CodeBehind is `~/App_Code/Services.vb`.
      # Consult the class index only when it was built up front; building
      # it here would race between worker fibers.
      if index = @class_index
        if name = directive_class_name(content)
          return index[name]?
        end
      end

      nil
    rescue
      nil
    end

    private def directive_class_name(content : String) : String?
      match = content.match(PAGE_DIRECTIVE_RE)
      return unless match

      name = directive_attributes(match[1])["class"]?
      return if name.nil? || name.empty?

      # `Class="Ns.Sub.Type"` — the index is keyed on the short name.
      name.split('.').last.downcase
    end

    private def resolve_reference(path : String, reference : String) : String?
      normalized = reference.gsub('\\', '/').strip
      return if normalized.empty?

      candidate =
        if normalized.starts_with?("~/")
          File.join(web_root_for(path), normalized[2..])
        elsif normalized.starts_with?("/")
          File.join(web_root_for(path), normalized[1..])
        else
          File.join(File.dirname(path), normalized)
        end

      lookup_file(File.expand_path(candidate))
    end

    private def scan_source(path : String, buckets : ParamBuckets)
      content = strip_comments(path, read_file_content(path))

      {ALIASED_COLLECTION_RE, REQUEST_COLLECTION_RE}.each do |pattern|
        content.scan(pattern) do |match|
          name = match[2]
          next if skip_field?(name)

          record_collection_read(match[1].downcase, name, buckets)
        end
      end

      content.scan(BARE_REQUEST_RE) do |match|
        name = match[1]
        next if skip_field?(name)

        buckets.add_ambiguous(name)
      end
    rescue e
      logger.debug "Error scanning #{path}: #{e}"
    end

    private def record_collection_read(collection : String, name : String, buckets : ParamBuckets)
      case collection
      when "querystring" then buckets.query << Param.new(name, "", "query")
      when "form"        then buckets.body << Param.new(name, "", "form")
      when "cookies"     then buckets.shared << Param.new(name, "", "cookie")
      when "headers"     then buckets.shared << Param.new(name, "", "header")
      when "params"      then buckets.add_ambiguous(name)
      when "servervariables"
        if header = http_header_name(name)
          buckets.shared << Param.new(header, "", "header")
        end
      end
    end

    private def emit_web_methods(url : String, sources : Array(String), details : Details)
      sources.each do |source|
        next if markup?(source)

        content = strip_comments(source, read_file_content(source))
        content.scan(WEBMETHOD_ATTR_RE) do |match|
          start = match.end(0)
          next unless start

          window = content[start, WEBMETHOD_WINDOW]? || ""
          signature = window.match(VB_SIGNATURE_RE) || window.match(CS_SIGNATURE_RE)
          next unless signature

          params = signature_params(signature[2]).map { |name| Param.new(name, "", "form") }
          # SOAP / ScriptService methods are POST-only; HTTP GET on a
          # web service has been disabled by default since .NET 2.0.
          @result << Endpoint.new("#{url}/#{signature[1]}", "POST", params, details)
        end
      rescue e
        logger.debug "Error extracting web methods from #{source}: #{e}"
      end
    end

    # `ByVal count As Integer` (VB) and `int count` (C#) both put the
    # name last once modifiers and the type suffix are removed.
    private def signature_params(raw : String) : Array(String)
      names = [] of String

      raw.split(',').each do |chunk|
        declaration = chunk.split(/\s+As\s+/i).first
        declaration = declaration.split('=').first.strip
        next if declaration.empty?

        name = declaration.split(/\s+/).last?
        next if name.nil? || !name.matches?(/\A[A-Za-z_]\w*\z/)

        names << name
      end

      names
    end

    private def skip_field?(name : String) : Bool
      name.empty? || FRAMEWORK_FIELDS.includes?(name.downcase)
    end

    private def markup?(path : String) : Bool
      extension = File.extname(path).downcase
      PAGE_EXTENSIONS.includes?(extension) || extension == ".ascx" || extension == ".master"
    end

    private def page_url(path : String) : String
      root = web_root_for(path)
      relative = get_relative_path(root, path).gsub(File::SEPARATOR, "/")
      relative.starts_with?("/") ? relative : "/#{relative}"
    end

    private def directory_url(url : String) : String
      directory = url.rpartition('/').first
      "#{directory}/"
    end

    # Deepest `Global.asax` ancestor, else a conventional root directory,
    # else the configured scan base.
    private def web_root_for(path : String) : String
      directory = File.dirname(path)
      best = nil.as(String?)

      webroots.each do |root|
        next unless directory == root || directory.starts_with?("#{root}#{File::SEPARATOR}")
        best = root if best.nil? || root.size > best.size
      end

      return best if best

      base = configured_base_for(path)
      relative = get_relative_path(base, path).gsub(File::SEPARATOR, "/")
      marker_index = -1
      WEBROOT_MARKERS.each do |marker|
        if index = relative.rindex(marker)
          candidate = index + marker.size
          marker_index = candidate if candidate > marker_index
        end
      end

      return base if marker_index < 0

      File.join(base, relative[0...marker_index])
    end

    private def webroots : Array(String)
      @webroots ||= all_files
        .select { |file| File.basename(file).downcase == GLOBAL_ASAX }
        .map { |file| File.dirname(file) }
        .uniq!
    end

    # Building the class index reads every `.vb`/`.cs` in the project, so
    # only pay for it when a service actually needs the fallback.
    private def class_index_needed?(pages : Array(String)) : Bool
      pages.any? do |path|
        next false unless SERVICE_EXTENSIONS.includes?(File.extname(path).downcase)
        next false unless code_behind_for(path).nil?

        !directive_class_name(read_file_content(path)).nil?
      rescue
        false
      end
    end

    private def build_class_index
      index = {} of String => String

      all_files.each do |file|
        extension = File.extname(file).downcase
        next unless extension == ".vb" || extension == ".cs"
        next if file.matches?(DESIGNER_FILE_RE)

        read_file_content(file).scan(CLASS_DEFINITION_RE) do |match|
          index[match[1].downcase] ||= file
        end
      rescue
        next
      end

      @class_index = index
    end

    private def file_index : Hash(String, String)
      @file_index ||= begin
        index = {} of String => String
        all_files.each { |file| index[File.expand_path(file).downcase] = file }
        index
      end
    end

    private def lookup_file(expanded : String) : String?
      file_index[expanded.downcase]?
    end

    private def directive_attributes(raw : String) : Hash(String, String)
      attributes = {} of String => String
      raw.scan(DIRECTIVE_ATTR_RE) do |match|
        attributes[match[1].downcase] = match[2]
      end
      attributes
    end

    # Line comments only. A real lexer buys ~1% precision here: across the
    # corpus commented-out reads are 9 of 785 VB reads and 2 of 378 C#
    # reads, and neither VB `""` escaping nor C# verbatim strings ever
    # appear inside a parameter key.
    #
    # The comment character is language-specific, and getting it wrong is
    # far more costly than the precision it buys. `'` only starts a
    # comment in VB: in C# it delimits a char literal (`sep == '/'`) and
    # in markup it quotes attributes — and single-quoted attributes are
    # the standard WebForms data-binding form (`Text='<%# Eval("x") %>'`),
    # so treating `'` as a comment there silently discarded the rest of
    # the line along with any request read on it.
    private def strip_comments(path : String, content : String) : String
      vb = File.extname(path).downcase == ".vb"

      String.build do |io|
        content.each_line(chomp: false) do |line|
          io << strip_line_comment(line, vb)
        end
      end
    end

    private def strip_line_comment(line : String, vb : Bool) : String
      in_string = false
      index = 0
      characters = line.chars

      while index < characters.size
        character = characters[index]

        if character == '"'
          in_string = !in_string
        elsif !in_string && comment_start?(character, characters[index + 1]?, vb)
          return "#{line[0...index]}\n"
        end

        index += 1
      end

      line
    end

    private def comment_start?(character : Char, following : Char?, vb : Bool) : Bool
      return character == '\'' if vb

      character == '/' && following == '/'
    end

    # Params split by the verb they can arrive on. Query and body stay
    # separate so a `Request.Form` read never surfaces as a GET param,
    # while cookies and headers apply to both.
    private struct ParamBuckets
      getter query = [] of Param
      getter body = [] of Param
      getter shared = [] of Param

      # `Request(...)` and `Request.Params[...]` search QueryString then
      # Form, so they genuinely belong to both verbs.
      def add_ambiguous(name : String)
        @query << Param.new(name, "", "query")
        @body << Param.new(name, "", "form")
      end

      def query_side : Array(Param)
        query + shared
      end

      def body_side : Array(Param)
        body + shared
      end
    end
  end
end
