# Part of NoirMobileLinker: resolving Android deep-link handlers (component -> .kt/.java
# source), extracting their callees and intent/bundle params.
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
end
