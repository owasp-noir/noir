require "../models/endpoint"
require "../models/code_locator"
require "../ext/tree_sitter/tree_sitter"
require "../miniparsers/kotlin_callee_extractor"
require "../miniparsers/java_callee_extractor"

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
  MOBILE_PROTOCOLS = Set{"mobile-scheme", "android-intent", "universal-link"}

  # Methods where an Android component reads its inbound intent / deep link.
  HANDLER_METHODS = %w[
    onCreate onNewIntent onStart onResume onStartCommand onHandleIntent
    handleIntent handleDeepLink onReceive onBind
  ]

  def self.apply(endpoints : Array(Endpoint), logger : NoirLogger) : Array(Endpoint)
    return endpoints unless endpoints.any? { |ep| android_handler_target?(ep) }

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

    endpoints
  end

  # An endpoint we can resolve to an Android component: a mobile protocol
  # with either a `via` class (scheme / universal-link) or an intent://
  # component URL (android-intent). iOS schemes carry neither.
  private def self.android_handler_target?(endpoint : Endpoint) : Bool
    return false unless MOBILE_PROTOCOLS.includes?(endpoint.protocol)
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
    callees.each { |callee| endpoint.push_callee(callee) }
    endpoint
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
end
