require "../models/endpoint"
require "../models/code_locator"
require "../utils/text_file"
require "./import_graph"
require "./extraction_result_cache"
require "../utils/js_literal_scanner"
require "../utils/top_level_split"
require "../utils/c_comments"

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
      @@wrapper_shapes.clear
      @@parameter_modules.clear
      @@sources.clear
      @@export_aliases.clear
      @@specifiers.clear
      @@spread_modules.clear
    end
  end

  # Definition files are read once per lookup otherwise: a barrel chain
  # (`controllers.write.posts.vote`) reads each module per hop and per name.
  @@sources = Hash(String, String?).new

  private def source(path : String) : String?
    found, cached = @@lock.synchronize { {@@sources.has_key?(path), @@sources[path]?} }
    return cached if found
    text = TextFile.read(path) rescue nil
    @@lock.synchronize { Noir::ExtractionResultCache.store_capped(@@sources, path, text, 512) }
  end

  # file (absolute) -> parameter of its exported function -> the module
  # (absolute) every caller passes there; see `RouteHelperScanner`.
  @@parameter_modules = Hash(String, Hash(String, String)).new

  def bind_parameter(file : String, name : String, module_path : String) : Nil
    @@lock.synchronize { (@@parameter_modules[Noir::PathScope.expand(file)] ||= Hash(String, String).new)[name] = module_path }
  end

  private def parameter_module(file_path : String, name : String) : String?
    found = @@lock.synchronize { @@parameter_modules[Noir::PathScope.expand(file_path)]?.try(&.[name]?) } || return
    return found if Path[file_path].absolute?
    Path[found].relative_to?(Dir.current).try(&.to_posix.to_s) || found
  end

  # `handler_text` is the route argument as written. Returns nil unless it
  # is a plain reference that resolves to a definition.
  def resolve(handler_text : String, content : String, file_path : String, guards : Bool = false) : Handler?
    text = handler_text.strip
    # `asyncHandler(withAuth(list))`: wrappers nest.
    3.times do
      inner = unwrap(text, content, file_path, guards) || break
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
        return follow_members(text, target, hops, members.last)
      end
      # `import users from './users'; users.create` → `create` in ./users;
      # `import { login } from './login'` → the exported `login`.
      wanted = member || spec[1] || base
      return exported_definition(text, target, wanted)
    end
    # `helpers.tryRoute` inside the module `const helpers = module.exports` defines.
    if member && base.matches?(export_aliases_re(content))
      return definition_line(file_path, members.join('.'), content).try { |line| Handler.new(text, file_path, line) }
    end
    # `module.exports = function (app, middleware, controllers)` whose callers
    # all hand it the same module.
    if members.size > 0 && (target = parameter_module(file_path, base))
      return follow_members(text, target, members[0...-1], members.last)
    end
    # `const controllers = { helpers: require('../controllers/helpers') }`.
    if members.size > 1 && (spec = local_require_member(content, base, members.first))
      target = resolve_specifier(file_path, spec) || return
      return follow_members(text, target, members[1...-1], members.last)
    end
    return if member # `security.isAuthorized` with `security` not imported here
    if line = definition_line(file_path, base, content, local: true)
      Handler.new(text, file_path, line)
    end
  end

  # `last` in the module `target` reaches through `hops`, each a member that
  # names a module; when one does not, the rest of the chain is a property
  # path the module exports (`Utilities.ping = {}; Utilities.ping.get = …`).
  private def follow_members(text : String, target : String, hops : Array(String), last : String) : Handler?
    hops.each_with_index do |hop, idx|
      # A property path the module defines wins over a module it merely
      # imports under the same name (`const flags = require('../flags')`
      # beside `modsController.flags.list = …`).
      if line = definition_line(target, hops[idx..].push(last).join('.'))
        return Handler.new(text, target, line)
      end
      target = member_module(target, hop) || return
    end
    exported_definition(text, target, last)
  end

  # The specifier of `member: require('…')` in the object literal a local
  # `base` is declared as.
  private def local_require_member(content : String, base : String, member : String) : String?
    decl = content.match(/\b(?:const|let|var)\s+#{Regex.escape(base)}\s*=\s*\{/) || return
    open = decl.end(0) - 1
    close = JSLiteralScanner.find_matching_brace(content, open) || return
    content[open..close].match(/(?:^|[{,])\s*#{Regex.escape(member)}\s*:\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/m).try(&.[1])
  end

  # A wrapper call `W(x)` as {`x`, its char offset in `text`, `W`}, when the
  # wrapper hands the request on to its argument: its definition takes a
  # function and returns one that calls it (`(fn) => (req, res, next) =>
  # Promise.resolve(fn(req, res, next)).catch(next)`). A wrapper with no
  # definition in the scan, or one whose definition cannot be read, is taken
  # by name (`WRAPPER_NAME_RE`). A wrapper that can itself refuse the request
  # (`(fn) => (req, res, next) => req.user ? fn(req, res, next) :
  # res.sendStatus(401)`) is a guard around `x`: it is only unwrapped when
  # the caller reports that guard (`guards: true`).
  def unwrap(text : String, content : String, file_path : String, guards : Bool = false) : Tuple(String, Int32, String)?
    m = text.match(WRAPPER_CALL_RE) || return
    open = m.end(0) - 1
    close = JSLiteralScanner.find_matching_paren(text, open) || return
    return unless text[close + 1..].blank?
    spans = TopLevelSplit.split_spans(text, ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS, open + 1, close).reject(&.[0].blank?)
    return if spans.empty?
    callee = m[1].gsub(/\s+/, "")
    definition = resolve(callee, content, file_path)
    shape = if definition && (path = definition.path) && (line = definition.line)
              wrapper_shape(path, line)
            end
    if shape
      forwarded, refuses = shape
      return unless forwarded
      return if refuses && !guards
    else
      # Only a definition says which argument is the wrapped function
      # (`tryRoute(controller, onError)`, `wrap2(onErr, fn)`).
      return unless spans.size == 1 && callee.matches?(WRAPPER_NAME_RE)
      forwarded = 0
    end
    arg, pos = spans[forwarded]? || return
    return if arg.blank?
    {arg.strip, pos + arg.size - arg.lstrip.size, callee}
  end

  # The wrapper head: `function name<T>(`, `name = <T extends H>(`,
  # `= async (`, `module.exports = (`, `export default function (`; or a
  # bare `= fn =>`.
  WRAPPER_HEAD_RE  = /\A[^\n]*?(?:\bfunction\b\s*\*?\s*[\w$]*\s*|(?:=|\bdefault\b)\s*(?:async\s+)?)(?:<[^\n]*?>\s*)?\(/
  WRAPPER_BARE_RE  = /\A[^\n]*?(?:=|\bdefault\b)\s*(?:async\s+)?([A-Za-z_$][\w$]*)\s*=>/
  WRAPPER_REFUSAL  = /\b(?:status|sendStatus|code)\s*\(\s*40[13]\b|\bstatus\s*=\s*40[13]\b|\.throw\s*\(\s*40[13]\b|\bredirect\s*\(|\bthrow\s+new\b/
  WRAPPER_MAX_SPAN = 4000

  @@wrapper_shapes = Hash(Tuple(String, Int32), Tuple(Int32?, Bool)?).new

  # The request parameter of the function a wrapper returns: `(req, res,
  # next) =>`, `function (req, res)`, `req =>`.
  WRAPPER_INNER_RE = /\bfunction\b\s*\*?\s*[\w$]*\s*\(\s*([A-Za-z_$][\w$]*)|\(\s*([A-Za-z_$][\w$]*)[^()]*\)\s*(?::[^=;{]*)?=>|(?<![\w$.])([A-Za-z_$][\w$]*)\s*=>/

  # {calls its function parameter with the request, can refuse on its own}
  # for the definition at `line` of `path`, read to the end of its
  # statement; nil when it is not a function of one named parameter. The
  # call must pass the request on (`fn(req, res, next)`, `fn.apply(this,
  # arguments)`, `fn(...args)`): `(check) => (req, res, next) => check(req)
  # ? next() : res.sendStatus(403)` consults its argument.
  private def wrapper_shape(path : String, line : Int32) : Tuple(Int32?, Bool)?
    key = {path, line}
    found, cached = @@lock.synchronize { {@@wrapper_shapes.has_key?(key), @@wrapper_shapes[key]?} }
    return cached if found
    shape = source(path).try do |text|
      lines = text.lines[line - 1, 200]? || next
      code = Noir::CComments.strip(lines.join('\n'), quotes: %("'`)).gsub(/"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\]|\\.)*`/, %(""))
      if head = code.match(WRAPPER_HEAD_RE)
        open = head.end(0) - 1
        close = JSLiteralScanner.find_matching_paren(code, open) || next
        names = TopLevelSplit.split(code[open + 1...close], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS).map do |param|
          param.match(/\A\s*([A-Za-z_$][\w$]*)\s*(?:[:?=]|\z)/).try(&.[1])
        end
        body_from = close + 1
      elsif bare = code.match(WRAPPER_BARE_RE)
        names = [bare[1]] of String?
        body_from = bare.end(0)
      else
        next
      end
      body = statement_extent(code, body_from)
      inner = body.match(WRAPPER_INNER_RE)
      request = inner.try { |mm| mm[1]? || mm[2]? || mm[3]? }
      # The parameter the returned function calls with its request
      # (`fn(req, res, next)`, `fn.apply(this, arguments)`, `fn(...args)`),
      # not one it hands an error (`onErr(e, req, res)`) or only consults
      # (`check(req) ? next() : …`).
      first_arg = request ? "\\.\\.\\.|#{Regex.escape(request)}\\s*," : "\\.\\.\\."
      forwarded = names.index do |name|
        name && body.matches?(/(?<![\w$.])#{Regex.escape(name)}\s*(?:\.\s*(?:call|apply)\s*\(|\(\s*(?:#{first_arg}))/)
      end
      forwarded = nil unless body.matches?(/=>|\bfunction\b/)
      {forwarded, body.matches?(WRAPPER_REFUSAL)}
    end
    @@lock.synchronize { @@wrapper_shapes[key] = shape }
    shape
  end

  # `code` from `from` to the end of the statement there: a `;` or a line
  # that starts a new top-level statement, outside any bracket.
  private def statement_extent(code : String, from : Int32) : String
    depth = 0
    idx = from
    stop = Math.min(code.size, from + WRAPPER_MAX_SPAN)
    while idx < stop
      case code[idx]
      when '(', '[', '{' then depth += 1
      when ')', ']', '}' then depth -= 1
      when ';'           then break if depth <= 0
      when '\n'
        nxt = code[idx + 1]?
        break if depth <= 0 && nxt && !nxt.whitespace? && !"})].?:=>&|+-*".includes?(nxt)
      end
      break if depth < 0
      idx += 1
    end
    code[from...idx]
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
    target = source(file).try do |text|
      e = Regex.escape(name)
      exported = export_aliases(text)
      re = /\bget\s+#{e}\s*\(\s*\)\s*\{\s*return\s+require\s*\(\s*['"]([^'"]+)['"]\s*\)\s*;?\s*\}|(?:^|[{,])\s*#{e}\s*:\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)|(?<![\w$.])(?:#{exported})\s*(?:\.\s*#{e}|\[\s*['"]#{e}['"]\s*\])\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)|\bexport\s*\*\s*as\s+#{e}\s+from\s*['"]([^'"]+)['"]/m
      spec = text.match(re).try { |mm| mm[1]? || mm[2]? || mm[3]? || mm[4]? }
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
  @@specifiers = Hash(Tuple(String, String), String?).new

  # Memoized: every route naming `controllers.x.y` resolves the same
  # specifiers, each a few `stat`s.
  private def resolve_specifier(from_file : String, specifier : String) : String?
    key = {from_file, specifier}
    found, cached = @@lock.synchronize { {@@specifiers.has_key?(key), @@specifiers[key]?} }
    return cached if found
    target = resolve_specifier_uncached(from_file, specifier)
    @@lock.synchronize { Noir::ExtractionResultCache.store_capped(@@specifiers, key, target) }
  end

  private def resolve_specifier_uncached(from_file : String, specifier : String) : String?
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
  # `strict`: only a definition of `name` itself, not the module's default
  # export standing in for it.
  # `local`: a bare name used in its own file (`app.post('/', install)`)
  # means the local definition before an exported one of the same name.
  private def definition_line(path : String, name : String, content : String? = nil, strict : Bool = false, local : Bool = false) : Int32?
    key = "#{name}\0#{strict}\0#{local}"
    cached = @@lock.synchronize { @@definitions[path]?.try(&.[key]?) }
    return (cached == 0 ? nil : cached) if cached
    content ||= source(path)
    line = content ? find_definition(content, name, strict, local) : nil
    @@lock.synchronize { (@@definitions[path] ||= Hash(String, Int32).new)[key] = line || 0 }
    line
  end

  SPREAD_REQUIRE = /\.\.\.\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)|^[ \t]*export\s*\*\s*from\s*['"]([^'"]+)['"]/m

  # `name` as exported by `target`, through `module.exports = {
  # ...require('./a'), ...require('./b') }` (a later spread wins) when the
  # module does not define it itself.
  private def exported_definition(text : String, target : String, name : String) : Handler
    spreads = spread_modules(target)
    if !spreads.empty? && !definition_line(target, name, strict: true)
      spreads.reverse_each do |spread|
        line = definition_line(spread, name, strict: true) || next
        return Handler.new(text, spread, line)
      end
    end
    Handler.new(text, target, definition_line(target, name))
  end

  @@spread_modules = Hash(String, Array(String)).new

  private def spread_modules(target : String) : Array(String)
    if hit = @@lock.synchronize { @@spread_modules[target]? }
      return hit
    end
    found = [] of String
    source(target).try &.scan(SPREAD_REQUIRE) do |m|
      resolve_specifier(target, m[1]? || m[2]).try { |spread| found << spread }
    end
    @@lock.synchronize { Noir::ExtractionResultCache.store_capped(@@spread_modules, target, found, 1024) }
  end

  @@export_aliases = Hash(UInt64, Tuple(String, Regex)).new

  # `export_aliases` as {alternation, whole-name regex}, once per source.
  private def export_alias_entry(content : String) : Tuple(String, Regex)
    key = content.hash
    if hit = @@lock.synchronize { @@export_aliases[key]? }
      return hit
    end
    names = ["module\\s*\\.\\s*exports", "exports"]
    content.scan(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:module\s*\.\s*)?exports\s*[;\n]/) { |m| names << Regex.escape(m[1]) }
    content.scan(/^[ \t]*module\s*\.\s*exports\s*=\s*([A-Za-z_$][\w$]*)\s*;?[ \t]*$/m) { |m| names << Regex.escape(m[1]) }
    alternation = names.uniq.join('|')
    entry = {alternation, Regex.new("\\A(?:#{alternation})\\z")}
    @@lock.synchronize { Noir::ExtractionResultCache.store_capped(@@export_aliases, key, entry, 1024) }
  end

  private def export_aliases_re(content : String) : Regex
    export_alias_entry(content)[1]
  end

  # Names the module's exports object goes by: `exports`, `module.exports`,
  # and a local bound to it (`const Posts = module.exports;`, or
  # `module.exports = Posts;` at the end), as an alternation.
  def export_aliases(content : String) : String
    export_alias_entry(content)[0]
  end

  DEFAULT_EXPORT_RE = /^[ \t]*(?:module\.)?exports\s*=|^[ \t]*export\s+default\b/m

  private def find_definition(content : String, name : String, strict : Bool = false, local : Bool = false) : Int32?
    # Every pattern but the default export spells the name: skip compiling
    # them for a file that never does (most hops of a barrel chain).
    unless content.includes?(name)
      return if strict || name.includes?('.')
      return content.match(DEFAULT_EXPORT_RE).try { |m| content.byte_slice(0, m.byte_begin(0)).count('\n') + 1 }
    end
    escaped = Regex.escape(name)
    exported = export_aliases(content)
    patterns = [
      # `Posts.vote = async (req, res) => …` on the exports object is what the
      # module exports under that name, whatever a function body nearby
      # declares locally (`const list = await load()`); `Posts.list = list`
      # only points at the definition below.
      /^[ \t]*(?:#{exported})\s*(?:\.\s*#{escaped}|\[\s*['"]#{escaped}['"]\s*\])\s*=(?!=)(?!\s*[A-Za-z_$][\w$]*\s*;?[ \t]*$)/m,
      /^[ \t]*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*#{escaped}\s*[(<]/m,
      # Not `const pagination = require('../pagination')`: that binds a
      # module, it defines nothing here.
      /^[ \t]*(?:export\s+)?(?:const|let|var)\s+#{escaped}\s*(?::|=(?!\s*require\s*\())/m,
      /^[ \t]*(?:export\s+)?class\s+#{escaped}\b/m,
      /^[ \t]*(?:export\s+)?(?:async\s+)?#{escaped}\s*\([^)]*\)\s*(?::[^{]*)?\{/m,
      /^[ \t]*#{escaped}\s*:\s*(?:async\s+)?(?:function\b|\(|\[)/m,
      /^[ \t]*(?:module\.)?exports(?:\.#{escaped})?\s*=|^[ \t]*export\s+default\b/m,
    ]
    # A property path (`ping.get`) is only ever an assignment on the exports
    # object, never the module's default export.
    patterns = patterns[0, 1] if name.includes?('.')
    exports_assignment = patterns[0]
    patterns = patterns[0...-1] if strict
    # A bare local name is never the module's nameless default export: `async
    # (req, res) =>` or an undeclared `check(req)` inside a router factory
    # resolved to the factory and read every route it registers.
    patterns = patterns[1...-1] + [patterns[0]] if local && !strict && patterns.size > 2
    patterns.each do |re|
      # Assigned twice (`exports.thing = …` again below): the last one is
      # what the module exports.
      m = re.same?(exports_assignment) ? content.scan(re).last? : content.match(re)
      if m
        return content.byte_slice(0, m.byte_begin(0)).count('\n') + 1
      end
    end
    nil
  end
end
