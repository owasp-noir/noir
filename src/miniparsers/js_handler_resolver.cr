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

  IMPORT_DEFAULT_RE = /\bimport\s+([A-Za-z_$][\w$]*)\s*(?:,\s*\{[^}]*\}\s*)?from\s*['"]([^'"]+)['"]/
  IMPORT_NAMED_RE   = /\bimport\s*(?:[A-Za-z_$][\w$]*\s*,\s*)?\{([^}]*)\}\s*from\s*['"]([^'"]+)['"]/
  IMPORT_STAR_RE    = /\bimport\s*\*\s*as\s+([A-Za-z_$][\w$]*)\s*from\s*['"]([^'"]+)['"]/
  REQUIRE_RE        = /\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/
  REQUIRE_NAMED_RE  = /\b(?:const|let|var)\s*\{([^}]*)\}\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/

  # name -> {specifier, exported name or nil for default/namespace}
  alias Imports = Hash(String, Tuple(String, String?))

  @@imports = Hash(String, Tuple(UInt64, Imports)).new
  @@definitions = Hash(String, Hash(String, Int32)).new

  def reset
    @@imports.clear
    @@definitions.clear
  end

  # `handler_text` is the route argument as written. Returns nil unless it
  # is a plain reference that resolves to a definition.
  def resolve(handler_text : String, content : String, file_path : String) : Handler?
    text = handler_text.strip
    return unless m = text.match(REFERENCE_RE)
    base, member = m[1], m[2]?

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

  private def imports_of(content : String, file_path : String) : Imports
    cached = @@imports[file_path]?
    return cached[1] if cached && cached[0] == content.hash
    @@imports[file_path] = {content.hash, begin
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
      imports
    end}
    @@imports[file_path][1]
  end

  # Relative specifiers only: a bare package name is not in the scan.
  private def resolve_specifier(from_file : String, specifier : String) : String?
    return unless specifier.starts_with?('.')
    boundary = CodeLocator.instance.scan_base_paths.find { |base| from_file.starts_with?(base) }
    resolved = Noir::ImportGraph.resolve_relative_import(from_file, specifier, boundary: boundary) || return
    # ImportGraph expands to an absolute path; report it the way the route's
    # own path is reported (relative when the scan base was), so `reach`
    # matches both the same way.
    return resolved if Path[from_file].absolute?
    Path[resolved].relative_to?(Dir.current).try(&.to_s) || resolved
  end

  # 1-based line of `name`'s definition in `path`, by the shapes a handler
  # is declared in; `module.exports =` / `export default` stand in for a
  # default import whose local name the target never spells.
  private def definition_line(path : String, name : String, content : String? = nil) : Int32?
    table = @@definitions[path] ||= Hash(String, Int32).new
    table.fetch(name) do
      content ||= TextFile.read(path) rescue nil
      line = content ? find_definition(content, name) : nil
      table[name] = line || 0
      line
    end.try { |l| l == 0 ? nil : l }
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
