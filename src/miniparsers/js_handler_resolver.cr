require "../models/endpoint"
require "../models/code_locator"
require "../utils/text_file"
require "./import_graph"

# Resolves a route's named handler (`app.get('/x', login)`,
# `router.post('/y', users.create)`, `app.use(auth())`) to the file and
# line that define it: a same-file `function login` / `const login =`, or
# the target of the import that brought the name in.
#
# Best-effort by design. An inline closure has no name, a package import
# (`express.static`) has no file in the scan, and a re-exported symbol is
# followed one hop only. Each of those yields nil rather than a guess.
module Noir::JSHandlerResolver
  extend self

  REFERENCE_RE = /\A([A-Za-z_$][\w$]*)(?:\s*\.\s*([A-Za-z_$][\w$]*))?\s*(?:\(\s*\))?\z/

  # `utils.asyncHandler(login())`, `wrap(ctrl.show)`: the handler is the
  # argument, the wrapper only catches its rejection. Only names that are
  # conventionally transparent; `validate(schema)` is middleware, not a
  # wrapped `schema`.
  # ponytail: a name list; reading the wrapper's body would be the upgrade.
  WRAPPER_RE = /\A(?:[A-Za-z_$][\w$]*\.)?(?:asyncHandler|asyncWrap|asyncWrapper|asyncMiddleware|wrap|wrapAsync|catchAsync|catchErrors|handleAsync|expressAsyncHandler|tryCatch|ah)\s*\((.+)\)\z/m

  # Factories that register middleware, never a route's handler. A route
  # whose last argument is one of these has no named handler to report.
  MIDDLEWARE_FACTORIES = Set{
    "cors", "helmet", "morgan", "compression", "cookieParser", "csrf", "csurf",
    "rateLimit", "serveStatic", "favicon", "session", "methodOverride", "multer",
    "bodyParser", "express", "passport", "serveIndex", "timeout", "responseTime",
  }

  IMPORT_DEFAULT_RE = /\bimport\s+([A-Za-z_$][\w$]*)\s*(?:,\s*\{[^}]*\}\s*)?from\s*['"]([^'"]+)['"]/
  IMPORT_NAMED_RE   = /\bimport\s*(?:[A-Za-z_$][\w$]*\s*,\s*)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/
  IMPORT_STAR_RE    = /\bimport\s*\*\s*as\s+([A-Za-z_$][\w$]*)\s*from\s*['"]([^'"]+)['"]/
  REQUIRE_RE        = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/
  REQUIRE_NAMED_RE  = /\b(?:const|let|var)\s*\{([^}]*)\}\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/

  # name -> {specifier, exported name or nil for default/namespace}
  alias Imports = Hash(String, Tuple(String, String?))

  @@imports = Hash(String, Tuple(UInt64, Imports)).new
  @@definitions = Hash(String, Hash(String, Int32)).new
  # Analyzers call in from parallel file-scan workers; the caches are
  # shared, so every read and write goes through this lock.
  @@lock = Mutex.new

  def reset
    @@lock.synchronize do
      @@imports.clear
      @@definitions.clear
      @@tsconfig_paths.clear
    end
  end

  # `handler_text` is the route argument as written. Returns nil unless it
  # is a plain reference that resolves to a definition.
  def resolve(handler_text : String, content : String, file_path : String) : Handler?
    text = handler_text.strip
    if wrapped = text.match(WRAPPER_RE)
      text = wrapped[1].strip
    end
    return unless m = text.match(REFERENCE_RE)
    base, member = m[1], m[2]?
    return if MIDDLEWARE_FACTORIES.includes?(base)

    if spec = imports_of(content, file_path)[base]?
      target = resolve_specifier(file_path, spec[0]) || return Handler.new(text)
      # `import users from './users'; users.create` → `create` in ./users;
      # `import { login } from './login'` → the exported `login`.
      wanted = member || spec[1] || base
      return Handler.new(text, target, definition_line(target, wanted))
    end
    return if member # `security.isAuthorized` with `security` not imported here
    if line = definition_line(file_path, base, content)
      Handler.new(text, file_path, line)
    end
  end

  # `await import("./x.handler")` in a handler body: `name` as exported by
  # the module `specifier` names, or its default export when nil.
  def resolve_module_export(specifier : String, name : String?, file_path : String) : Handler?
    target = resolve_specifier(file_path, specifier) || return
    wanted = name || "default"
    Handler.new(wanted, target, definition_line(target, wanted))
  end

  def imports_of(content : String, file_path : String) : Imports
    hash = content.hash
    cached = @@lock.synchronize { @@imports[file_path]? }
    return cached[1] if cached && cached[0] == hash
    imports = Imports.new
    content.scan(IMPORT_DEFAULT_RE) { |m| imports[m[1]] = {m[2], nil} }
    content.scan(IMPORT_STAR_RE) { |m| imports[m[1]] = {m[2], nil} }
    content.scan(REQUIRE_RE) { |m| imports[m[1]] = {m[2], nil} }
    {IMPORT_NAMED_RE, REQUIRE_NAMED_RE}.each do |re|
      content.scan(re) do |m|
        m[1].split(',').each do |entry|
          parts = entry.split(/\s+as\s+|\s*:\s*/, 2).map(&.strip)
          exported = parts[0]
          local = parts[1]? || exported
          next if local.empty?
          imports[local] = {m[2], exported}
        end
      end
    end
    @@lock.synchronize { @@imports[file_path] = {hash, imports} }
    imports
  end

  # Relative specifiers, and tsconfig `paths` aliases that map onto one: a
  # bare package name is not in the scan.
  private def resolve_specifier(from_file : String, specifier : String) : String?
    boundary = CodeLocator.instance.scan_base_paths.find { |base| from_file.starts_with?(base) }
    unless specifier.starts_with?('.')
      target = tsconfig_alias_target(from_file, specifier, boundary) || return
      relative = Path[target].relative_to(File.dirname(Noir::PathScope.expand(from_file))).to_posix.to_s
      specifier = relative.starts_with?("..") ? relative : "./#{relative}"
    end
    resolved = Noir::ImportGraph.resolve_relative_import(from_file, specifier, boundary: boundary) || return
    # ImportGraph expands to an absolute path; report it the way the route's
    # own path is reported (relative when the scan base was), so `reach`
    # matches both the same way.
    return resolved if Path[from_file].absolute?
    Path[resolved].relative_to?(Dir.current).try(&.to_posix.to_s) || resolved
  end

  TSCONFIG_PATHS_RE    = /"paths"\s*:\s*\{([^}]*)\}/m
  TSCONFIG_ENTRY_RE    = /"([^"\s]+)"\s*:\s*\[\s*"([^"\s]+)"/
  TSCONFIG_BASE_URL_RE = /"baseUrl"\s*:\s*"([^"]+)"/

  # pattern -> first target, resolved against baseUrl (or the tsconfig's dir)
  @@tsconfig_paths = Hash(String, Array(Tuple(String, String))).new

  # The absolute path `specifier` names through `compilerOptions.paths` of
  # the nearest tsconfig.json at or above `from_file` that declares any
  # (`"@server/*": ["./server/*"]`), without leaving the scan base.
  # ponytail: first target only, `extends` not followed.
  private def tsconfig_alias_target(from_file : String, specifier : String, boundary : String?) : String?
    dir = File.dirname(Noir::PathScope.expand(from_file))
    stop = boundary.try { |b| Noir::PathScope.expand(b) }
    loop do
      aliases = tsconfig_paths(File.join(dir, "tsconfig.json"))
      unless aliases.empty?
        aliases.each do |pattern, target|
          if pattern.ends_with?('*') && target.ends_with?('*')
            stem = pattern.rchop('*')
            return target.rchop('*') + specifier.lchop(stem) if specifier.starts_with?(stem)
          elsif pattern == specifier
            return target
          end
        end
        return
      end
      parent = File.dirname(dir)
      break if parent == dir || (stop && !parent.starts_with?(stop))
      dir = parent
    end
    nil
  end

  private def tsconfig_paths(tsconfig : String) : Array(Tuple(String, String))
    cached = @@lock.synchronize { @@tsconfig_paths[tsconfig]? }
    return cached if cached
    aliases = [] of Tuple(String, String)
    if File.file?(tsconfig) && (text = TextFile.read(tsconfig) rescue nil) && (block = text.match(TSCONFIG_PATHS_RE))
      base = File.expand_path(text.match(TSCONFIG_BASE_URL_RE).try(&.[1]) || ".", File.dirname(tsconfig))
      block[1].scan(TSCONFIG_ENTRY_RE) { |m| aliases << {m[1], File.expand_path(m[2], base)} }
      aliases.sort_by! { |pattern, _| -pattern.size } # TypeScript takes the longest matching prefix
    end
    @@lock.synchronize { @@tsconfig_paths[tsconfig] = aliases }
    aliases
  end

  # 1-based line of `name`'s definition in `path`, by the shapes a handler
  # is declared in; `module.exports =` / `export default` stand in for a
  # default import whose local name the target never spells.
  private def definition_line(path : String, name : String, content : String? = nil) : Int32?
    cached = @@lock.synchronize { @@definitions[path]?.try(&.[name]?) }
    return (cached == 0 ? nil : cached) if cached
    content ||= TextFile.read(path) rescue nil
    line = content ? find_definition(content, name) : nil
    @@lock.synchronize { (@@definitions[path] ||= Hash(String, Int32).new)[name] = line || 0 }
    line
  end

  private def find_definition(content : String, name : String) : Int32?
    escaped = Regex.escape(name)
    patterns = [
      /^[ \t]*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*#{escaped}\s*[(<]/m,
      /^[ \t]*(?:export\s+)?(?:const|let|var)\s+#{escaped}\s*[:=]/m,
      /^[ \t]*(?:export\s+)?class\s+#{escaped}\b/m,
      /^[ \t]*(?:export\s+)?(?:async\s+)?#{escaped}\s*\([^)]*\)\s*(?::[^{]*)?\{/m,
      /^[ \t]*#{escaped}\s*:\s*(?:async\s+)?(?:function\b|\()/m,
      /^[ \t]*(?:module\.)?exports(?:\.#{escaped})?\s*=|^[ \t]*export\s+default\b/m,
    ]
    patterns.each do |re|
      if m = content.match(re)
        return content.byte_slice(0, m.byte_begin(0)).count('\n') + 1
      end
    end
    nil
  end
end
