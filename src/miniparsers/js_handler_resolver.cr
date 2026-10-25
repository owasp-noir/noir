require "../models/endpoint"
require "../models/code_locator"
require "../utils/text_file"
require "./import_graph"
require "../utils/js_literal_scanner"
require "../utils/top_level_split"

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

  REFERENCE_RE = /\A([A-Za-z_$][\w$]*)((?:\s*\.\s*[A-Za-z_$][\w$]*)*)\s*(?:\(\s*\))?\z/

  # `utils.asyncHandler(login())`, `wrap(ctrl.show)`: the handler is the
  # argument, the wrapper only catches its rejection. A wrapper defined in
  # the scan is judged by its definition (`unwrap`); these names are the
  # fallback for one that comes from a package (`express-async-handler`).
  # `validate(schema)` is middleware, not a wrapped `schema`.
  WRAPPER_NAME_RE = /(?:\A|\.)(?:asyncHandler|asyncWrap|asyncWrapper|asyncMiddleware|wrap|wrapAsync|catchAsync|catchErrors|handleAsync|expressAsyncHandler|tryCatch|ah)\z/
  WRAPPER_CALL_RE = /\A((?:[A-Za-z_$][\w$]*\s*\.\s*)?[A-Za-z_$][\w$]*)\s*\(/

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
  REQUIRE_RE        = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)(?:\s*\.\s*([A-Za-z_$][\w$]*))?/
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
      @@member_modules.clear
      @@transparent.clear
    end
  end

  # `handler_text` is the route argument as written. Returns nil unless it
  # is a plain reference that resolves to a definition.
  def resolve(handler_text : String, content : String, file_path : String) : Handler?
    text = handler_text.strip
    if inner = unwrap(text, content, file_path)
      text = inner[0]
    end
    return unless m = text.match(REFERENCE_RE)
    base = m[1]
    members = m[2].split('.').map(&.strip).reject(&.empty?)
    member = members.last?
    return if MIDDLEWARE_FACTORIES.includes?(base)

    if spec = imports_of(content, file_path)[base]?
      target = resolve_specifier(file_path, spec[0]) || return Handler.new(text)
      # `auth.authorize.check`: every member but the last names a module
      # (`get authorize() { return require('./authorize') }`).
      if members.size > 1
        hops = members[0...-1]
        spec[1].try { |exported| hops.unshift(exported) }
        hops.each { |hop| target = member_module(target, hop) || return }
        return Handler.new(text, target, definition_line(target, members.last))
      end
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

  # `asyncHandler(fn)` as `fn` and its char offset in `text`, when the
  # wrapper hands the request on to its argument: its definition takes a
  # function and returns one that calls it (`(fn) => (req, res, next) =>
  # Promise.resolve(fn(req, res, next)).catch(next)`). A wrapper with no
  # definition in the scan is taken by name (`WRAPPER_NAME_RE`).
  def unwrap(text : String, content : String, file_path : String) : Tuple(String, Int32)?
    m = text.match(WRAPPER_CALL_RE) || return
    open = m.end(0) - 1
    close = JSLiteralScanner.find_matching_paren(text, open) || return
    return unless text[close + 1..].blank?
    spans = TopLevelSplit.split_spans(text, ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS, open + 1, close)
    return unless spans.size == 1
    arg, pos = spans[0]
    return if arg.blank?
    callee = m[1].gsub(/\s+/, "")
    definition = resolve(callee, content, file_path)
    transparent = if definition && (path = definition.path) && (line = definition.line)
                    transparent_wrapper?(path, line)
                  else
                    callee.matches?(WRAPPER_NAME_RE)
                  end
    return unless transparent
    {arg.strip, pos + arg.size - arg.lstrip.size}
  end

  @@transparent = Hash(Tuple(String, Int32), Bool).new

  # The definition at `line` of `path` takes a parameter, returns a function,
  # and calls that parameter with the request (`fn(req, res, next)`,
  # `fn.apply(this, arguments)`, `fn(...args)`). `(check) => (req, res, next)
  # => check(req) ? next() : res.sendStatus(403)` consults its argument; it
  # does not hand the request to it.
  # ponytail: read to the next top-level declaration (12 lines at most), not
  # parsed; a wrapper spelled over more lines is not unwrapped.
  private def transparent_wrapper?(path : String, line : Int32) : Bool
    key = {path, line}
    cached = @@lock.synchronize { @@transparent[key]? }
    return cached unless cached.nil?
    found = (TextFile.read(path) rescue nil).try do |text|
      lines = text.lines[line - 1, 12]? || [] of String
      lines = lines.each_with_index.take_while { |row, idx| idx == 0 || !row.matches?(/\A(?:export|const|let|var|function|class|module|import)\b/) }.map(&.[0])
      code = lines.join('\n')
      param = code.match(/(?:\bfunction\b[^(]*|[:=]\s*(?:async\s+)?)\(\s*([A-Za-z_$][\w$]*)|[:=]\s*(?:async\s+)?([A-Za-z_$][\w$]*)\s*=>/) || next false
      name = param[1]? || param[2]
      rest = code[param.end(0)..]
      rest.matches?(/=>|\bfunction\b/) && rest.matches?(/(?<![\w$.])#{Regex.escape(name)}\s*(?:\.\s*(?:call|apply)\s*\(|\(\s*(?:\.\.\.|[\w$]+\s*,))/)
    end || false
    @@lock.synchronize { @@transparent[key] = found }
    found
  end

  @@member_modules = Hash(Tuple(String, String), String?).new

  # The module `file` exposes as its member `name`: a lazy getter or a
  # property that `require`s it, `exports.name = require(…)`, or a whole
  # module imported under that name (`const session = require('./session')`
  # exported as `{ session }`). Nil when the member is not a module.
  private def member_module(file : String, name : String) : String?
    key = {file, name}
    found, cached = @@lock.synchronize { {@@member_modules.has_key?(key), @@member_modules[key]?} }
    return cached if found
    target = (TextFile.read(file) rescue nil).try do |text|
      e = Regex.escape(name)
      re = /\bget\s+#{e}\s*\(\s*\)\s*\{\s*return\s+require\s*\(\s*['"]([^'"]+)['"]\s*\)\s*;?\s*\}|(?:^|[{,])\s*#{e}\s*:\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)|\bexports\.#{e}\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/m
      spec = text.match(re).try { |mm| mm[1]? || mm[2]? || mm[3]? }
      spec ||= imports_of(text, file)[name]?.try { |imp| imp[0] unless imp[1] }
      spec.try { |sp| resolve_specifier(file, sp) }
    end
    @@lock.synchronize { @@member_modules[key] = target }
    target
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
    # `require('./m').foo` binds the module's `foo`, as `{ foo } = require` does.
    content.scan(REQUIRE_RE) { |m| imports[m[1]] = {m[2], m[3]?.try { |prop| prop == "default" ? nil : prop }} }
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
      /^[ \t]*#{escaped}\s*:\s*(?:async\s+)?(?:function\b|\(|\[)/m,
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
