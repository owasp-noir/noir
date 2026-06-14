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
# endpoints have no per-endpoint `via`, so the linker discovers central
# App/SceneDelegate/SwiftUI handlers and attaches them by deep-link kind.
module NoirMobileLinker
  # Methods where an Android component reads its inbound intent / deep link.
  # onCreateView / onViewCreated cover Jetpack Navigation fragment
  # destinations, which receive deep-link path/query values as arguments.
  HANDLER_METHODS = %w[
    onCreate onNewIntent onStart onResume onStartCommand onHandleIntent
    handleIntent handleDeepLink onReceive onBind onCreateView onViewCreated
  ]

  # ContentProvider entry points. A provider is reached via ContentResolver,
  # so its inbound data (the `uri`, `selection`, `selectionArgs`, projection)
  # arrives through these methods rather than an Intent — `query` / `openFile`
  # are the classic SQL-injection / path-traversal sinks. Kept separate from
  # HANDLER_METHODS so these generic verbs are only scanned for provider
  # components, not grafted onto every activity that happens to have an
  # `update()`.
  PROVIDER_HANDLER_METHODS = %w[
    onCreate query insert update delete bulkInsert openFile openAssetFile call getType applyBatch
  ]

  # Inputs the handler reads from the inbound deep link. `getQueryParameter`
  # reads a real URI query parameter (surfaced as a "query" param, baked
  # into the URL like any other); the `get*Extra` family reads Intent extras
  # (a Bundle, not part of the URI) and is surfaced as the "extra" type.
  QUERY_PARAM_RE  = /\.getQueryParameter\s*\(\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_.]*))/
  EXTRA_PARAM_RE  = /\.(?:get\w*Extra|hasExtra)\s*\(\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_.]*))/
  BUNDLE_PARAM_RE = /\b(?:arguments|requireArguments\(\)|getArguments\(\)|savedStateHandle|extras|intent\.extras|intent\.getExtras\(\))\??\s*\.\s*get(?:String|Int|Integer|Boolean|Long|Float|Double|Char|Byte|Short|Parcelable|Serializable|StringArray|CharSequence|Bundle)?(?:\s*<[^>]+>)?\s*\(\s*(?:"([^"]+)"|'([^']+)'|([A-Za-z_][A-Za-z0-9_.]*))/

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
    handler_cache = {} of String => HandlerInfo
    endpoints.each_with_index do |endpoint, i|
      next unless android_handler_target?(endpoint)
      cls = handler_class(endpoint)
      next if cls.nil?

      resolved = index.resolve(cls[:simple], cls[:package])
      next unless resolved

      begin
        is_provider = provider_endpoint?(endpoint)
        methods = is_provider ? PROVIDER_HANDLER_METHODS : HANDLER_METHODS
        cache_key = "#{resolved[:lang]}:#{resolved[:path]}:#{cls[:simple]}:#{is_provider}"
        info = handler_cache[cache_key]? || begin
          fresh = android_handler_info(cls[:simple], resolved[:path], resolved[:lang], methods)
          handler_cache[cache_key] = fresh
          fresh
        end
        endpoints[i] = apply_handler_info(endpoint, info)
      rescue e
        logger.debug "Mobile linker failed for #{endpoint.url} (#{resolved[:path]}): #{e.message}"
      end
    end
  end

  # iOS: deep links are dispatched centrally (App/SceneDelegate), so there is
  # no per-endpoint `via`. Discover handlers within the endpoint's Xcode
  # project root and attach by kind — URL handlers (onOpenURL /
  # application(open:) / scene(openURLContexts:)) to custom schemes,
  # userActivity handlers to universal links. Scoping matters for monorepos
  # that ship multiple iOS apps; a Focus AppDelegate should not become Firefox
  # Browser evidence just because both live in the same repository checkout.
  private def self.link_ios(endpoints : Array(Endpoint), logger : NoirLogger)
    return unless endpoints.any? { |ep| ios_handler_target?(ep) }

    handlers_by_scope = {} of String => Hash(Symbol, HandlerInfo)

    endpoints.each_with_index do |endpoint, i|
      next unless ios_handler_target?(endpoint)
      scope = ios_handler_scope(endpoint)
      key = scope || ""
      handlers = handlers_by_scope[key]?
      unless handlers
        begin
          handlers = IosHandlers.discover(scope)
          handlers_by_scope[key] = handlers
        rescue e
          logger.debug "Mobile linker (iOS) handler discovery failed#{scope ? " for #{scope}" : ""}: #{e.message}"
          next
        end
      end

      info = endpoint.protocol == "universal-link" ? handlers[:activity] : handlers[:url]
      next if info.empty?
      endpoints[i] = apply_handler_info(endpoint, info)
    end
  end

  private def self.ios_handler_target?(endpoint : Endpoint) : Bool
    endpoint.mobile? && endpoint.details.technology == "ios"
  end

  private def self.ios_handler_scope(endpoint : Endpoint) : String?
    config_path = endpoint.details.code_paths.find do |path_info|
      File.basename(path_info.path) == "Info.plist" || path_info.path.ends_with?(".entitlements")
    end || endpoint.details.code_paths.first?
    return unless config_path

    IosHandlers.xcode_project_root(config_path.path) || IosHandlers.nearest_handler_source_root(config_path.path)
  end

  private def self.apply_handler_info(endpoint : Endpoint, info : HandlerInfo) : Endpoint
    info.code_paths.each { |pi| endpoint.details.add_path(pi) }
    info.callees.each { |callee| endpoint.push_callee(callee) }
    info.params.each { |param| endpoint.push_param(param) }
    endpoint
  end

  # An endpoint we can resolve to an Android component: a mobile protocol
  # with either a `via` class (scheme / universal-link / provider) or an
  # intent:// component URL (android-intent). iOS schemes carry neither.
  private def self.android_handler_target?(endpoint : Endpoint) : Bool
    return false unless endpoint.mobile?
    return true if endpoint.url.starts_with?("intent://")
    !!(endpoint.metadata.try &.has_key?("via"))
  end

  private def self.provider_endpoint?(endpoint : Endpoint) : Bool
    endpoint.protocol == "android-provider"
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

  private def self.android_handler_info(simple : String, path : String, lang : Symbol,
                                        handler_methods : Array(String) = HANDLER_METHODS) : HandlerInfo
    info = HandlerInfo.new
    content = read_content(path) || ""

    callees = [] of Callee
    if lang == :kotlin
      Noir::TreeSitter.parse_kotlin(content) do |root|
        handler_methods.each do |method|
          Noir::KotlinCalleeExtractor.callees_in_method(root, content, path, simple, method).each do |name, fpath, line|
            append_android_callee(callees, name, fpath, line)
          end
        end
        android_delegate_methods(callees).each do |delegate|
          target_line = delegate[:line].try { |line| line - 1 }
          Noir::KotlinCalleeExtractor.callees_in_method(root, content, path, simple, delegate[:name], target_line).each do |name, fpath, line|
            append_android_callee(callees, name, fpath, line)
          end
        end
      end
    else
      Noir::TreeSitter.parse_java(content) do |root|
        handler_methods.each do |method|
          Noir::JavaCalleeExtractor.callees_in_method(root, content, path, simple, method).each do |name, fpath, line|
            append_android_callee(callees, name, fpath, line)
          end
        end
        android_delegate_methods(callees).each do |delegate|
          target_line = delegate[:line].try { |line| line - 1 }
          Noir::JavaCalleeExtractor.callees_in_method(root, content, path, simple, delegate[:name], target_line).each do |name, fpath, line|
            append_android_callee(callees, name, fpath, line)
          end
        end
      end
    end

    callees = prioritize_android_callees(callees)
    anchor_line = handler_anchor_line(content, simple, handler_methods)
    info.code_paths << PathInfo.new(path, anchor_line)
    extract_input_params(callees, content).each { |param| info.params << param }
    callees.first(Callee::MAX_PER_ENDPOINT).each do |callee|
      info.callees << callee
      if android_delegate_callee?(callee)
        if callee_path = callee.path
          info.code_paths << PathInfo.new(callee_path, callee.line)
        end
      end
    end
    info
  end

  private def self.append_android_callee(callees : Array(Callee), name : String, path : String, line : Int32)
    callee = Callee.new(name, path: path, line: line)
    callees << callee unless callees.includes?(callee)
  end

  # Android lifecycle methods often perform large amounts of UI setup before
  # they touch the inbound Intent/Uri. Keep the bounded callee list focused on
  # deep-link handling, input reads, dispatch, and sinks so important calls are
  # not pushed out by `setContentView` / `findViewById` noise.
  private def self.prioritize_android_callees(callees : Array(Callee)) : Array(Callee)
    scored = [] of Tuple(Callee, Int32, Int32)
    callees.each_with_index do |callee, index|
      score = android_callee_score(callee)
      scored << {callee, score, index} unless score < 0
    end

    scored.sort_by! { |entry| {-entry[1], entry[0].line || Int32::MAX, entry[2]} }
    scored.map(&.[0])
  end

  private def self.android_callee_score(callee : Callee) : Int32
    name = callee.name
    return -1 if android_noise_callee?(name)

    score = 0
    score += 100 if android_input_callee?(name)
    score += 90 if android_mobile_sink_callee?(name)
    score += 80 if name.matches?(/\b(create|destroy|delete|update|save|insert|remove|persist|clear|wipe|reset)\w*/i)
    score += 70 if android_delegate_name?(name)
    score += 40 if name.matches?(/\b(?:service|repository|repo|dao|manager|client|gateway|api)\b/i)
    score
  end

  private def self.android_noise_callee?(name : String) : Bool
    return true if name.starts_with?("super.")
    return true if name.starts_with?("savedInstanceState.")
    return true if name.starts_with?("BuildConfig.")
    return true if name.starts_with?("ThemeHelper.")
    return true if name.starts_with?("TextUtils.")
    return true if name.starts_with?("Log.")
    return true if name.starts_with?("ThemeSwitcher.")
    return true if name.starts_with?("ThemeUtils.")
    return true if name.starts_with?("viewBinding.")
    return true if name == "Bridge.restoreInstanceState"
    return true if name.matches?(/\Aget(?:String|Text|Color|Drawable)\z/)
    return true if name == "finish"
    return true if name.matches?(/(?:^|\.)(?:removeExtra|setData|setAction)\b/)
    return true if name.matches?(/(?:^|\.)(?:update\w*(?:Menu|Icon|Card|View|Text|Title|Toolbar|Layout)|set\w*(?:Text|Selection|Visibility|Enabled|Checked))\b/)
    return true if name.matches?(/(?:^|\.)(?:setContentView|findViewById|setSupportActionBar|setTheme|setTitle|invalidateOptionsMenu|getWindow|getActionBar|getSupportActionBar|getSupportFragmentManager|getOnBackPressedDispatcher|setVolumeControlStream|setProgressBarIndeterminateVisibility|getLayoutInflater|setOnClickListener|setCardBackgroundColor)\b/)
    return true if name.matches?(/(?:^|\.)(?:getFragments|registerFragmentLifecycleCallbacks|unregisterFragmentLifecycleCallbacks)\b/)
    return true if name.matches?(/(?:^|\.)(?:updatePadding|setOnWindowInsetsChangeListener|getInsets)\b/)
    return true if name.matches?(/\b\w+Binding\.inflate\b/)
    return true if name.matches?(/\b(?:systemBars|ime|Toast\.makeText)\b/)
    false
  end

  private def self.android_input_callee?(name : String) : Bool
    return true if name.matches?(/(?:^|\.)(?:getIntent|getData|getDataString|getExtras|get\w+Extra|getQueryParameter|getArguments|requireArguments)\b/)
    name.matches?(/(?:^|\.)(?:arguments|savedStateHandle|extras|bundle)\.get(?:String|Int|Boolean|Long|Parcelable|Serializable)\b/i)
  end

  private def self.android_mobile_sink_callee?(name : String) : Bool
    # WebView / intent-forwarding sinks, plus the ContentProvider data sinks
    # (raw SQL and file descriptors) reachable from an exported provider's
    # query/openFile handlers.
    name.matches?(/(?:^|\.)(?:loadUrl|loadData|loadDataWithBaseURL|evaluateJavascript|startActivity|startActivityForResult|sendBroadcast|startService|bindService|rawQuery|execSQL|compileStatement|openOrCreateDatabase|ParcelFileDescriptor)\b/)
  end

  private def self.android_delegate_callee?(callee : Callee) : Bool
    return false unless callee.path && callee.line
    android_delegate_name?(callee.name)
  end

  private def self.android_delegate_methods(callees : Array(Callee)) : Array(NamedTuple(name: String, line: Int32?))
    methods = [] of NamedTuple(name: String, line: Int32?)
    seen = Set(String).new

    callees.each do |callee|
      next unless android_delegate_callee?(callee)
      method = callee.name.split('.').last
      next if method.empty? || HANDLER_METHODS.includes?(method)
      next unless seen.add?(method)

      methods << {name: method, line: callee.line}
    end

    methods
  end

  private def self.android_delegate_name?(name : String) : Bool
    name.matches?(/(?:^|\.)(?:handle|route|dispatch|open|process|parse|resolve|prepare|lookup|download|fetch|validate|subscribe|get\w*Url|onSuccess|onFailure|show\w*Dialog)\w*/i)
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
      src.scan(QUERY_PARAM_RE) { |m| params << Param.new(param_name(m), "", "query") }
      src.scan(EXTRA_PARAM_RE) { |m| params << Param.new(param_name(m), "", "extra") }
      src.scan(BUNDLE_PARAM_RE) { |m| params << Param.new(param_name(m), "", "extra") }
    end
    params
  end

  private def self.param_name(match : Regex::MatchData) : String
    raw = match[1]? || match[2]? || match[3]? || ""
    raw.split('.').last
  end

  # Best-effort source line for the handler so the AI-context snippet window
  # covers the intent-reading code: prefer the first handler-method
  # declaration, fall back to the class declaration.
  private def self.handler_anchor_line(content : String, simple : String,
                                       handler_methods : Array(String) = HANDLER_METHODS) : Int32?
    method_re = /\b(?:fun|void|public|protected|private|override)\b.*\b(?:#{handler_methods.join("|")})\s*\(/
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

    SWIFT_HANDLER_HINTS = [
      "openURLContexts",
      "open url:",
      "continue userActivity:",
      ".onOpenURL",
      ".onContinueUserActivity",
    ]
    OBJC_HANDLER_HINTS = [
      "openURL:",
      "openURLContexts:",
      "continueUserActivity:",
    ]

    IOS_CALLEE_NOISE = Set{
      "URL",
      "URLRequest",
      "URLComponents",
      "NSURLComponents",
      "componentsWithURL",
      "isEqualToString",
      "host",
      "shared",
      "URLContexts.first",
      "print",
      "Task",
      "UIApplication.shared.canOpenURL",
      "Notification.Name",
      "NotificationCenter.default.post",
      "UserDefaults.standard.bool",
      "AppContainer.shared.resolve",
      "routeBuilder.configure",
    }

    XCODE_PROJECT_SEARCH_DEPTH =  6
    MAX_FORWARDED_ACTIONS      =  8
    MAX_FORWARDED_CASES        = 24

    record ForwardedAction, receiver : String, method : String, action : String, action_type : String

    def self.discover(scope_root : String? = nil) : Hash(Symbol, NoirMobileLinker::HandlerInfo)
      url = NoirMobileLinker::HandlerInfo.new
      activity = NoirMobileLinker::HandlerInfo.new
      expanded_scope = scope_root.try { |root| File.expand_path(root).rstrip('/') }

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless swift_handler_candidate?(content)
        scan_file(path, content, url, activity,
          URL_HANDLER_RES, ACTIVITY_HANDLER_RES, SIGNATURE_START_RE, expanded_scope, objc: false)
      end

      {".m", ".mm"}.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          next unless in_scope?(path, expanded_scope)
          next if skip_ios_source?(path)
          content = NoirMobileLinker.read_content(path)
          next unless content
          next unless objc_handler_candidate?(content)
          scan_file(path, content, url, activity,
            OBJC_URL_HANDLER_RES, OBJC_ACTIVITY_HANDLER_RES, OBJC_SIGNATURE_START_RE, expanded_scope, objc: true)
        end
      end

      {:url => url, :activity => activity}
    end

    def self.xcode_project_root(path : String) : String?
      dir = File.dirname(File.expand_path(path))
      XCODE_PROJECT_SEARCH_DEPTH.times do
        has_project = !Dir.glob(File.join(dir, "*.xcodeproj")).empty? ||
                      !Dir.glob(File.join(dir, "*.xcworkspace")).empty?
        return dir if has_project
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    def self.nearest_handler_source_root(path : String) : String?
      dir = File.dirname(File.expand_path(path))
      XCODE_PROJECT_SEARCH_DEPTH.times do
        return dir if ios_handler_source_under?(dir)

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    private def self.in_scope?(path : String, scope_root : String?) : Bool
      return true unless scope_root

      expanded = File.expand_path(path)
      expanded == scope_root || expanded.starts_with?(scope_root + "/")
    end

    private def self.ios_handler_source_under?(root : String) : Bool
      expanded_root = File.expand_path(root).rstrip('/')

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_root)
        next if skip_ios_source?(path)
        content = NoirMobileLinker.read_content(path)
        return true if content && swift_handler_candidate?(content)
      end

      {".m", ".mm"}.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          next unless in_scope?(path, expanded_root)
          next if skip_ios_source?(path)
          content = NoirMobileLinker.read_content(path)
          return true if content && objc_handler_candidate?(content)
        end
      end

      false
    end

    private def self.skip_ios_source?(path : String) : Bool
      normalized = path.gsub('\\', '/')
      basename = File.basename(normalized)
      normalized.includes?("/.build/") || normalized.includes?("/.swiftpm/") ||
        normalized.includes?("/Pods/") || normalized.includes?("/Carthage/") ||
        normalized.includes?("/DerivedData/") || normalized.includes?("/SourcePackages/") ||
        normalized.includes?("/Tests/") || normalized.includes?("/UITests/") ||
        normalized.includes?("/UnitTests/") || normalized.includes?("/SnapshotTests/") ||
        normalized.includes?("/TestSupport/") || normalized.includes?("/Generated/") ||
        basename.ends_with?("Tests.swift") || basename.ends_with?("Test.swift") ||
        basename.ends_with?(".generated.swift")
    end

    private def self.swift_handler_candidate?(content : String) : Bool
      SWIFT_HANDLER_HINTS.any? { |hint| content.includes?(hint) }
    end

    private def self.objc_handler_candidate?(content : String) : Bool
      OBJC_HANDLER_HINTS.any? { |hint| content.includes?(hint) }
    end

    # Scans one source file for the central deep-link dispatch handlers,
    # accumulating callees (and Swift query params) into the shared
    # `url` / `activity` handler info. `objc` selects the Objective-C handler
    # patterns + callee extractor; otherwise the Swift ones are used.
    private def self.scan_file(path : String, content : String,
                               url : NoirMobileLinker::HandlerInfo,
                               activity : NoirMobileLinker::HandlerInfo,
                               url_res : Array(Regex), activity_res : Array(Regex),
                               sig_re : Regex, expanded_scope : String?, objc : Bool)
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

        append_code_path(target, path, index + 1)
        callees = objc ? Noir::ObjcCalleeExtractor.callees_for_body(body, path, body_line) : Noir::SwiftCalleeExtractor.callees_for_body(body, path, body_line)
        append_callees(target, callees)
        # Query params read from the inbound URL, per dialect.
        name_re, item_re = objc ? {OBJC_QUERY_NAME_RE, OBJC_QUERY_ITEM_RE} : {QUERY_NAME_RE, QUERY_ITEM_RE}
        append_query_params(target, body, name_re, item_re)

        next if objc

        append_swift_local_method_info(path, content, callees, target, name_re, item_re)
        append_swift_forwarded_action_info(body, content, expanded_scope, target, name_re, item_re)
      end
    end

    private def self.append_code_path(info : NoirMobileLinker::HandlerInfo, path : String, line : Int32)
      return if info.code_paths.any? { |pi| pi.path == path && pi.line == line }

      info.code_paths << PathInfo.new(path, line)
    end

    private def self.append_callees(info : NoirMobileLinker::HandlerInfo, callees : Array(Tuple(String, String, Int32)))
      callees.each do |name, fpath, fline|
        next if ios_callee_noise?(name)
        next if info.callees.any? { |callee| callee.name == name && callee.path == fpath }

        info.callees << Callee.new(name, path: fpath, line: fline)
      end
    end

    private def self.append_query_params(info : NoirMobileLinker::HandlerInfo, body : String, name_re : Regex, item_re : Regex)
      body.scan(name_re) { |m| append_query_param(info, m[1]) }
      body.scan(item_re) { |m| append_query_param(info, m[1]) }
    end

    private def self.append_query_param(info : NoirMobileLinker::HandlerInfo, name : String)
      return if info.params.any? { |param| param.name == name && param.param_type == "query" }

      info.params << Param.new(name, "", "query")
    end

    # Many iOS apps keep the delegate handler tiny and immediately forward the
    # inbound URL to a same-file helper (`routeOpenURL(url)`,
    # `handleDeepLink(url)`). Follow only URL/deep-link-shaped helpers one
    # level so AI context sees the real sinks/guards without walking arbitrary
    # application call graphs.
    private def self.append_swift_local_method_info(path : String, content : String,
                                                    callees : Array(Tuple(String, String, Int32)),
                                                    target : NoirMobileLinker::HandlerInfo,
                                                    name_re : Regex, item_re : Regex)
      seen = Set(String).new
      callees.each do |name, _, _|
        next unless local_swift_method_candidate?(name)
        next unless seen.add?(name)
        method = swift_method_body(content, name)
        next unless method

        append_code_path(target, path, method[:line])
        nested = Noir::SwiftCalleeExtractor.callees_for_body(method[:body], path, method[:body_line])
        append_callees(target, nested)
        append_query_params(target, method[:body], name_re, item_re)
      end
    end

    # DuckDuckGo-style lifecycle code forwards `application(_:open:)` into a
    # state machine action: `appStateMachine.handle(.openURL(url))`, with the
    # real branch in `case .openURL`. Follow URL/deep-link action cases within
    # the same Xcode project scope, then apply the same local-helper expansion
    # to the case body.
    private def self.append_swift_forwarded_action_info(body : String,
                                                        handler_content : String,
                                                        expanded_scope : String?,
                                                        target : NoirMobileLinker::HandlerInfo,
                                                        name_re : Regex, item_re : Regex)
      actions = forwarded_swift_actions(body, handler_content, expanded_scope)
      return if actions.empty?

      cases_seen = 0
      actions.each do |action|
        CodeLocator.instance.files_by_extension(".swift").each do |path|
          next unless in_scope?(path, expanded_scope)
          next if skip_ios_source?(path)
          content = NoirMobileLinker.read_content(path)
          next unless content
          next unless content.includes?("case .#{action.action}")

          cases_seen += scan_swift_action_cases(path, content, action, target, name_re, item_re, MAX_FORWARDED_CASES - cases_seen)
          return if cases_seen >= MAX_FORWARDED_CASES
        end
      end
    end

    private def self.forwarded_swift_actions(body : String, handler_content : String,
                                             expanded_scope : String?) : Array(ForwardedAction)
      actions = [] of ForwardedAction
      body.scan(/(?:self\.)?([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |m|
        receiver = m[1]
        method = m[2]
        action = m[3]
        next unless swift_deep_link_name?(action)
        receiver_type = swift_receiver_type(handler_content, receiver)
        next unless receiver_type
        action_type = swift_forwarded_action_type(receiver_type, method, action, expanded_scope)
        next unless action_type
        forwarded = ForwardedAction.new(receiver, method, action, action_type)
        next if actions.any? { |existing| existing == forwarded }

        actions << forwarded
        break if actions.size >= MAX_FORWARDED_ACTIONS
      end
      actions
    end

    private def self.scan_swift_action_cases(path : String, content : String, action : ForwardedAction,
                                             target : NoirMobileLinker::HandlerInfo,
                                             name_re : Regex, item_re : Regex,
                                             remaining : Int32) : Int32
      return 0 if remaining <= 0

      found = 0
      case_re = Regex.new("^\\s*case\\s+\\.#{Regex.escape(action.action)}\\b")

      swift_method_bodies(content, action.method, action.action_type).each do |method|
        lines = method[:body].lines
        depth = 0
        in_string = false

        lines.each_with_index do |line, index|
          stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
          next unless stripped.matches?(case_re)

          case_body, relative_body_line = swift_case_body(lines, index)
          case_line = method[:body_line] + index
          body_line = method[:body_line] + relative_body_line - 1
          append_code_path(target, path, case_line)
          callees = Noir::SwiftCalleeExtractor.callees_for_body(case_body, path, body_line)
          append_callees(target, callees)
          append_query_params(target, case_body, name_re, item_re)
          append_swift_local_method_info(path, content, callees, target, name_re, item_re)

          found += 1
          return found if found >= remaining
        end
      end

      found
    end

    private def self.swift_receiver_type(content : String, receiver : String) : String?
      escaped = Regex.escape(receiver)
      explicit_re = Regex.new("\\b(?:let|var)\\s+#{escaped}\\s*:\\s*([A-Za-z_][A-Za-z0-9_]*)\\b")
      inferred_re = Regex.new("\\b(?:let|var)\\s+#{escaped}\\s*=\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")

      content.match(explicit_re).try(&.[1]) || content.match(inferred_re).try(&.[1])
    end

    private def self.swift_forwarded_action_type(receiver_type : String, method : String, action : String,
                                                 expanded_scope : String?) : String?
      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless content.includes?(receiver_type) && content.includes?("func #{method}")

        swift_type_method_parameter_types(content, receiver_type, method).each do |action_type|
          return action_type if swift_enum_has_case?(action_type, action, expanded_scope)
        end
      end

      nil
    end

    private def self.swift_type_method_parameter_types(content : String, receiver_type : String,
                                                       method : String) : Array(String)
      type_re = Regex.new("\\b(?:class|struct|actor|enum)\\s+#{Regex.escape(receiver_type)}\\b")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(type_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        body, _ = body_after_opening_brace(lines, brace[:index], brace[:col])
        return swift_method_parameter_types(body, method)
      end

      [] of String
    end

    private def self.swift_method_parameter_types(content : String, method : String) : Array(String)
      types = [] of String
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(method)}\\s*\\(")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        signature = lines[index..brace[:index]].join(" ")
        signature.scan(/:\s*([A-Za-z_][A-Za-z0-9_]*)\b/) do |m|
          type = m[1]
          types << type unless types.includes?(type)
        end
      end

      types
    end

    private def self.swift_enum_has_case?(enum_name : String, case_name : String,
                                          expanded_scope : String?) : Bool
      enum_re = Regex.new("\\benum\\s+#{Regex.escape(enum_name)}\\b")
      case_re = Regex.new("^\\s*case\\s+#{Regex.escape(case_name)}\\b")

      CodeLocator.instance.files_by_extension(".swift").each do |path|
        next unless in_scope?(path, expanded_scope)
        next if skip_ios_source?(path)
        content = NoirMobileLinker.read_content(path)
        next unless content
        next unless content.includes?("enum #{enum_name}") && content.includes?("case #{case_name}")

        lines = content.lines
        lines.each_with_index do |line, index|
          next unless line.matches?(enum_re)
          brace = find_opening_brace(lines, index)
          next unless brace
          body, _ = body_after_opening_brace(lines, brace[:index], brace[:col])
          return true if body.lines.any?(&.matches?(case_re))
        end
      end

      false
    end

    private def self.swift_method_bodies(content : String, method : String,
                                         parameter_type : String) : Array(NamedTuple(body: String, line: Int32, body_line: Int32))
      bodies = [] of NamedTuple(body: String, line: Int32, body_line: Int32)
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(method)}\\s*\\(")
      parameter_re = Regex.new(":\\s*#{Regex.escape(parameter_type)}\\b")
      lines = content.lines
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        signature = lines[index..brace[:index]].join(" ")
        next unless signature.matches?(parameter_re)

        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])
        bodies << {body: body, line: index + 1, body_line: body_line}
      end

      bodies
    end

    private def self.swift_case_body(lines : Array(String), case_index : Int32) : Tuple(String, Int32)
      case_line = lines[case_index]
      case_indent = leading_whitespace_width(case_line)
      body_lines = [] of String
      body_line = case_index + 2

      if colon = case_line.index(':')
        after_colon = case_line[(colon + 1)..]? || ""
        unless after_colon.strip.empty?
          body_lines << after_colon
          body_line = case_index + 1
        end
      end

      index = case_index + 1
      while index < lines.size
        line = lines[index]
        stripped = line.strip
        indent = leading_whitespace_width(line)

        break if !stripped.empty? && indent <= case_indent &&
                 (stripped.starts_with?("case ") || stripped.starts_with?("default") || stripped == "}")
        break if !stripped.empty? && indent < case_indent

        body_lines << line
        index += 1
      end

      {body_lines.join("\n"), body_line}
    end

    private def self.leading_whitespace_width(line : String) : Int32
      width = 0
      line.each_char do |char|
        case char
        when ' '
          width += 1
        when '\t'
          width += 4
        else
          break
        end
      end
      width
    end

    private def self.swift_method_body(content : String, name : String) : NamedTuple(body: String, line: Int32, body_line: Int32)?
      lines = content.lines
      method_re = Regex.new("\\bfunc\\s+#{Regex.escape(name)}\\s*\\(")
      depth = 0
      in_string = false

      lines.each_with_index do |line, index|
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        next unless stripped.matches?(method_re)

        brace = find_opening_brace(lines, index)
        next unless brace
        body, body_line = body_after_opening_brace(lines, brace[:index], brace[:col])
        return {body: body, line: index + 1, body_line: body_line}
      end

      nil
    end

    private def self.local_swift_method_candidate?(name : String) : Bool
      return false unless name.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      swift_deep_link_name?(name) || name.downcase.includes?("route")
    end

    private def self.swift_deep_link_name?(name : String) : Bool
      downcased = name.downcase
      downcased.includes?("url") || downcased.includes?("deeplink") ||
        downcased.includes?("deep_link") || downcased.includes?("link")
    end

    private def self.ios_callee_noise?(name : String) : Bool
      return true if IOS_CALLEE_NOISE.includes?(name)
      return true if name.starts_with?("Logger.")
      return true if name.ends_with?(".host")
      return true if name.ends_with?(".path")
      return true if name.ends_with?(".windowUUID")
      return true if name.includes?("queryItems") && name.ends_with?(".first")
      return true if name.includes?("URLContexts") && name.ends_with?(".first")

      false
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
