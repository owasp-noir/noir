require "../models/endpoint"
require "../models/code_locator"
require "../ext/tree_sitter/tree_sitter"
require "../miniparsers/kotlin_callee_extractor"
require "../miniparsers/java_callee_extractor"
require "../miniparsers/swift_callee_extractor"
require "../miniparsers/objc_callee_extractor"

# Post-analysis pass that links mobile deep-link endpoints (produced by the
# config-file analyzers from AndroidManifest.xml) to the source code that
# handles them. For each Android mobile endpoint it:
#
#   1. resolves the handling component (metadata["via"] / the intent://
#      component) to its .kt/.java source file,
#   2. adds that file as a `code_path` so the AI-context builder scans the
#      handler body for sinks/guards, and
#   3. extracts the handler's 1-hop callees into `endpoint.callees`.
#
# The existing AIContext builder then derives sinks/guards/sources from the
# handler snippet and callees — no mobile-specific wiring needed there. iOS
# endpoints (no `via`, dispatched by the App/SceneDelegate) are left for a
# follow-up.
module NoirMobileLinker
  # Methods where an Android component reads its inbound intent / deep link.
  # onCreateView / onViewCreated cover Jetpack Navigation fragment
  # destinations, which receive deep-link path/query values as arguments.
  HANDLER_METHODS = %w[
    onCreate onNewIntent onStart onResume onStartCommand onHandleIntent
    handleIntent handleDeepLink onReceive onBind onCreateView onViewCreated
  ]

  # Inputs the handler reads from the inbound deep link. `getQueryParameter`
  # reads a real URI query parameter (surfaced as a "query" param, baked
  # into the URL like any other); the `get*Extra` family reads Intent extras
  # (a Bundle, not part of the URI) and is surfaced as the "extra" type.
  QUERY_PARAM_RE = /\.getQueryParameter\s*\(\s*"([^"]+)"/
  EXTRA_PARAM_RE = /\.get(?:String|Int|Integer|Boolean|Long|Float|Double|Char|Byte|Short|Parcelable|Serializable|StringArray|CharSequence|Bundle)Extra\s*\(\s*"([^"]+)"/

  def self.apply(endpoints : Array(Endpoint), logger : NoirLogger) : Array(Endpoint)
    link_android(endpoints, logger)
    link_ios(endpoints, logger)
    endpoints
  end

  # Android: each component maps to its own handler class (metadata["via"] /
  # the intent:// component), resolved per endpoint.
  private def self.link_android(endpoints : Array(Endpoint), logger : NoirLogger)
    return unless endpoints.any? { |ep| android_handler_target?(ep) }

    index = ClassIndex.new
    endpoints.each_with_index do |endpoint, i|
      next unless android_handler_target?(endpoint)
      cls = handler_class(endpoint)
      next if cls.nil?

      resolved = index.resolve(cls[:simple], cls[:package])
      next unless resolved

      begin
        endpoints[i] = link_handler(endpoint, cls[:simple], resolved[:path], resolved[:lang])
      rescue e
        logger.debug "Mobile linker failed for #{endpoint.url} (#{resolved[:path]}): #{e.message}"
      end
    end
  end

  # iOS: deep links are dispatched centrally (App/SceneDelegate), so there is
  # no per-endpoint `via`. Discover the handlers once and attach by kind —
  # URL handlers (onOpenURL / application(open:) / scene(openURLContexts:))
  # to custom schemes, userActivity handlers to universal links.
  private def self.link_ios(endpoints : Array(Endpoint), logger : NoirLogger)
    return unless endpoints.any? { |ep| ios_handler_target?(ep) }

    begin
      handlers = IosHandlers.discover
    rescue e
      logger.debug "Mobile linker (iOS) handler discovery failed: #{e.message}"
      return
    end

    endpoints.each_with_index do |endpoint, i|
      next unless ios_handler_target?(endpoint)
      info = endpoint.protocol == "universal-link" ? handlers[:activity] : handlers[:url]
      next if info.empty?
      endpoints[i] = apply_handler_info(endpoint, info)
    end
  end

  private def self.ios_handler_target?(endpoint : Endpoint) : Bool
    endpoint.mobile? && endpoint.details.technology == "ios"
  end

  private def self.apply_handler_info(endpoint : Endpoint, info : HandlerInfo) : Endpoint
    info.code_paths.each { |pi| endpoint.details.add_path(pi) }
    info.callees.each { |callee| endpoint.push_callee(callee) }
    info.params.each { |param| endpoint.push_param(param) }
    endpoint
  end

  # An endpoint we can resolve to an Android component: a mobile protocol
  # with either a `via` class (scheme / universal-link) or an intent://
  # component URL (android-intent). iOS schemes carry neither.
  private def self.android_handler_target?(endpoint : Endpoint) : Bool
    return false unless endpoint.mobile?
    return true if endpoint.url.starts_with?("intent://")
    !!(endpoint.metadata.try &.has_key?("via"))
  end

  # Returns the handler class as {simple, package}. `via` is like
  # ".DeepLinkActivity" (relative to package) or a fully-qualified name; an
  # intent:// URL encodes "<package>/<component>".
  private def self.handler_class(endpoint : Endpoint) : NamedTuple(simple: String, package: String)?
    if via = endpoint.metadata.try &.["via"]?
      package = endpoint.metadata.try(&.["package"]?) || ""
      return class_parts(via, package)
    end

    if endpoint.url.starts_with?("intent://")
      rest = endpoint.url.lchop("intent://")
      package, _, component = rest.partition('/')
      component = rest if component.empty?
      return class_parts(component, package)
    end

    nil
  end

  private def self.class_parts(name : String, package : String) : NamedTuple(simple: String, package: String)
    name = name.lchop('.')
    if name.includes?('.')
      pkg, _, simple = name.rpartition('.')
      {simple: simple, package: pkg}
    else
      {simple: name, package: package}
    end
  end

  # Content cache may be cold (budget exhausted, or caching disabled in
  # tests); fall back to a direct read per the CodeLocator contract.
  def self.read_content(path : String) : String?
    cached = CodeLocator.instance.content_for(path)
    return cached if cached
    return unless File.exists?(path)
    File.read(path, encoding: "utf-8", invalid: :skip)
  end

  private def self.link_handler(endpoint : Endpoint, simple : String,
                                path : String, lang : Symbol) : Endpoint
    content = read_content(path) || ""

    callees = [] of Callee
    if lang == :kotlin
      Noir::TreeSitter.parse_kotlin(content) do |root|
        HANDLER_METHODS.each do |method|
          Noir::KotlinCalleeExtractor.callees_in_method(root, content, path, simple, method).each do |name, fpath, line|
            callees << Callee.new(name, path: fpath, line: line)
          end
        end
      end
    else
      Noir::TreeSitter.parse_java(content) do |root|
        HANDLER_METHODS.each do |method|
          Noir::JavaCalleeExtractor.callees_in_method(root, content, path, simple, method).each do |name, fpath, line|
            callees << Callee.new(name, path: fpath, line: line)
          end
        end
      end
    end

    anchor_line = handler_anchor_line(content, simple)
    endpoint.details.add_path(PathInfo.new(path, anchor_line))
    extract_input_params(callees, content).each { |param| endpoint.push_param(param) }
    callees.each { |callee| endpoint.push_callee(callee) }
    endpoint
  end

  # Extracts inbound-deep-link reads from the *handler-method* call sites
  # only. `callees` come from `callees_in_method` over HANDLER_METHODS, so
  # scanning their source lines (rather than the whole file) keeps reads in
  # unrelated methods of the same component from becoming phantom params.
  private def self.extract_input_params(callees : Array(Callee), content : String) : Array(Param)
    lines = content.lines
    params = [] of Param
    callees.each do |callee|
      line = callee.line
      next unless line && line >= 1 && line <= lines.size
      src = lines[line - 1]
      src.scan(QUERY_PARAM_RE) { |m| params << Param.new(m[1], "", "query") }
      src.scan(EXTRA_PARAM_RE) { |m| params << Param.new(m[1], "", "extra") }
    end
    params
  end

  # Best-effort source line for the handler so the AI-context snippet window
  # covers the intent-reading code: prefer the first handler-method
  # declaration, fall back to the class declaration.
  private def self.handler_anchor_line(content : String, simple : String) : Int32?
    method_re = /\b(?:fun|void|public|protected|private|override)\b.*\b(?:#{HANDLER_METHODS.join("|")})\s*\(/
    class_re = /\b(?:class|object)\s+#{Regex.escape(simple)}\b/
    class_line : Int32? = nil

    content.each_line.with_index do |line, idx|
      return idx + 1 if line.matches?(method_re)
      class_line = idx + 1 if class_line.nil? && line.matches?(class_re)
    end

    class_line
  end

  # Lazily indexes every project .kt/.java file by the simple names it
  # declares, so a manifest component name resolves to a file in O(1) after
  # one content scan. Disambiguates by package when several files share a
  # class name.
  class ClassIndex
    record Entry, path : String, lang : Symbol, package : String

    DECL_RE    = /\b(?:class|object|interface)\s+([A-Z]\w*)/
    PACKAGE_RE = /^\s*package\s+([\w.]+)/

    def initialize
      @index = Hash(String, Array(Entry)).new
      @built = false
    end

    def resolve(simple : String, package : String) : NamedTuple(path: String, lang: Symbol)?
      build unless @built
      entries = @index[simple]?
      return unless entries

      entry = entries.find { |e| !package.empty? && e.package == package } || entries.first
      {path: entry.path, lang: entry.lang}
    end

    private def build
      @built = true
      locator = CodeLocator.instance
      {".kt" => :kotlin, ".java" => :java}.each do |ext, lang|
        locator.files_by_extension(ext).each do |path|
          content = NoirMobileLinker.read_content(path)
          next unless content
          package = content.match(PACKAGE_RE).try(&.[1]) || ""
          content.scan(DECL_RE) do |m|
            (@index[m[1]] ||= [] of Entry) << Entry.new(path, lang.as(Symbol), package)
          end
        end
      end
    end
  end

  # Aggregated handler evidence to graft onto an endpoint.
  struct HandlerInfo
    getter code_paths : Array(PathInfo)
    getter callees : Array(Callee)
    getter params : Array(Param)

    def initialize
      @code_paths = [] of PathInfo
      @callees = [] of Callee
      @params = [] of Param
    end

    def empty? : Bool
      @code_paths.empty? && @callees.empty? && @params.empty?
    end
  end

  # Scans .swift files once for the central deep-link dispatch handlers and
  # groups their callees/params by kind. URL handlers process custom schemes;
  # userActivity handlers process universal links.
  module IosHandlers
    # Same-line markers for the brace that opens a handler body.
    URL_HANDLER_RES = [
      /\.onOpenURL\s*\{/,
      /\bfunc\s+application\s*\(.*\bopen\s+url\s*:/,
      /\bfunc\s+scene\s*\(.*\bopenURLContexts\b/,
    ]
    ACTIVITY_HANDLER_RES = [
      /\bfunc\s+application\s*\(.*\bcontinue\s+userActivity\s*:/,
      /\bfunc\s+scene\s*\(.*\bcontinue\s+userActivity\s*:/,
      /\.onContinueUserActivity\s*\(/,
    ]
    # Opening of an `application(...)` / `scene(...)` delegate method whose
    # parameter list may wrap across lines; used to fold the signature
    # before classifying it against the handler patterns above.
    SIGNATURE_START_RE = /\bfunc\s+(?:application|scene)\s*\(/

    # Objective-C counterparts. The same delegate methods are written as
    # message-style declarations: `- (BOOL)application:(UIApplication *)app
    # openURL:(NSURL *)url options:…`. Matched on the folded signature, so a
    # wrapped parameter list still classifies.
    OBJC_URL_HANDLER_RES = [
      /\bapplication:.*\bopenURL:/,
      /\bscene:.*\bopenURLContexts:/,
    ]
    OBJC_ACTIVITY_HANDLER_RES = [
      /\bapplication:.*\bcontinueUserActivity:/,
      /\bscene:.*\bcontinueUserActivity:/,
    ]
    OBJC_SIGNATURE_START_RE = /^\s*[+-]\s*\([^)]*\)\s*(?:application|scene):/

    # URLQueryItem name comparisons inside a handler — the iOS analog of
    # Android's getQueryParameter. Anchored to the closure-shorthand form
    # (`$0.name == "x"`) and an explicit `URLQueryItem(name: "x")` so a plain
    # `user.name == "admin"` comparison can't become a phantom query param.
    QUERY_NAME_RE = /\$\d+\.name\s*==\s*"([^"]+)"/
    QUERY_ITEM_RE = /URLQueryItem\(\s*name:\s*"([^"]+)"/

    # Objective-C query reads. The dominant idiom is iterating
    # `components.queryItems` and comparing the item's `name` against a
    # literal — `[item.name isEqualToString:@"token"]` (e.g. VLC reads
    # plexToken / payment_intent this way). Anchored to `.name` / `name]`
    # (not a bare `isEqualToString:`) so a `[host isEqualToString:@"new"]`
    # check can't become a phantom param. Also the explicit query-item
    # constructor.
    OBJC_QUERY_NAME_RE = /(?:\.name|\bname\])\s+isEqualToString:\s*@"([^"]+)"/
    OBJC_QUERY_ITEM_RE = /\bqueryItemWithName:\s*@"([^"]+)"/

    def self.discover : Hash(Symbol, NoirMobileLinker::HandlerInfo)
      url = NoirMobileLinker::HandlerInfo.new
      activity = NoirMobileLinker::HandlerInfo.new

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next if skip_ios_source?(path)
        content = NoirMobileLinker.read_content(path)
        next unless content
        scan_file(path, content, url, activity,
          URL_HANDLER_RES, ACTIVITY_HANDLER_RES, SIGNATURE_START_RE, objc: false)
      end

      {".m", ".mm"}.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          next if skip_ios_source?(path)
          content = NoirMobileLinker.read_content(path)
          next unless content
          scan_file(path, content, url, activity,
            OBJC_URL_HANDLER_RES, OBJC_ACTIVITY_HANDLER_RES, OBJC_SIGNATURE_START_RE, objc: true)
        end
      end

      {:url => url, :activity => activity}
    end

    private def self.skip_ios_source?(path : String) : Bool
      path.includes?("/.build/") || path.includes?("/.swiftpm/") ||
        path.includes?("/Pods/") || path.includes?("/Carthage/")
    end

    # Scans one source file for the central deep-link dispatch handlers,
    # accumulating callees (and Swift query params) into the shared
    # `url` / `activity` handler info. `objc` selects the Objective-C handler
    # patterns + callee extractor; otherwise the Swift ones are used.
    private def self.scan_file(path : String, content : String,
                               url : NoirMobileLinker::HandlerInfo,
                               activity : NoirMobileLinker::HandlerInfo,
                               url_res : Array(Regex), activity_res : Array(Regex),
                               sig_re : Regex, objc : Bool)
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)

        # A handler's signature may span several lines (SwiftLint / Objective-C
        # both wrap long parameter lists), e.g.
        #   func application(
        #     _ app: UIApplication,
        #     open url: URL
        #   ) -> Bool {
        # so when a line opens such a signature, fold it through to the body
        # brace before matching — otherwise no single line carries both the
        # method name and the `openURL` / `continueUserActivity` discriminator.
        signature = stripped
        if stripped.matches?(sig_re) && !stripped.includes?('{')
          if sig_brace = find_opening_brace(lines, index)
            signature = lines[index..sig_brace[:index]].join(" ")
          end
        end

        target = if url_res.any? { |re| signature.matches?(re) }
                   url
                 elsif activity_res.any? { |re| signature.matches?(re) }
                   activity
                 end
        next unless target

        brace = find_opening_brace(lines, index)
        next unless brace
        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])

        target.code_paths << PathInfo.new(path, index + 1)
        callees = objc ? Noir::ObjcCalleeExtractor.callees_for_body(body, path, body_line) : Noir::SwiftCalleeExtractor.callees_for_body(body, path, body_line)
        callees.each do |name, fpath, fline|
          target.callees << Callee.new(name, path: fpath, line: fline)
        end
        # Query params read from the inbound URL, per dialect.
        name_re, item_re = objc ? {OBJC_QUERY_NAME_RE, OBJC_QUERY_ITEM_RE} : {QUERY_NAME_RE, QUERY_ITEM_RE}
        body.scan(name_re) { |m| target.params << Param.new(m[1], "", "query") }
        body.scan(item_re) { |m| target.params << Param.new(m[1], "", "query") }
      end
    end

    # Finds the first `{` at/after the matched line (same line, else within a
    # few lines for a func whose parameter list and/or brace wrap onto their
    # own lines — a folded multi-line signature can run several lines before
    # the body brace).
    private def self.find_opening_brace(lines : Array(String), start : Int32) : NamedTuple(index: Int32, col: Int32)?
      idx = start
      while idx < lines.size && idx <= start + 6
        col = lines[idx].index('{')
        return {index: idx, col: col} if col
        idx += 1
      end
      nil
    end

    # Brace-matched body text starting just after lines[opening_index][col],
    # ignoring braces inside comments/strings. Ported from the Swift analyzers'
    # shared body_after_opening_brace.
    private def self.body_after_opening_brace(lines : Array(String), opening_index : Int32, col : Int32) : Tuple(String, Int32)
      first = lines[opening_index][(col + 1)..]? || ""
      clean, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first, 0, false)
      brace = 1 + clean.count('{') - clean.count('}')
      if brace <= 0
        # Single-line body: trim the closing `}` and anything after it so a
        # trailing `.padding()` etc. doesn't leak into the handler body.
        closing = clean.rindex('}')
        return {closing ? first[0...closing] : first, opening_index + 1}
      end

      body = [first]
      idx = opening_index + 1
      while idx < lines.size && brace > 0
        line = lines[idx]
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        nxt = brace + stripped.count('{') - stripped.count('}')
        if nxt <= 0
          closing = stripped.rindex('}')
          body << (closing ? line[0...closing] : line) unless line.strip == "}"
          break
        end
        body << line
        brace = nxt
        idx += 1
      end

      {body.join("\n"), opening_index + 1}
    end
  end
end
