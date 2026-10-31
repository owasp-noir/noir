require "../utils/text_file"
require "../utils/path_scope"
require "../utils/utils"
require "./extraction_result_cache"
require "../models/code_locator"

module Noir
  # Shared file-level import-graph traversal for cross-file route /
  # DTO resolution.
  #
  # Today the JVM-style flavour is implemented (Java, Kotlin): a file
  # belongs to a package whose dotted path is reflected in its
  # directory layout (`src/main/java/com/foo/Bar.java` ↔
  # `package com.foo`), and imports map to file paths under the
  # inferred source root. This is the pattern called out as
  # duplication in #1107 for `TreeSitterJavaDtoIndex` and
  # `TreeSitterKotlinDtoIndex`.
  #
  # Caveats / non-goals:
  #
  #   * Python / Ruby / JS-style cross-file resolution doesn't share
  #     this exact source-root inference. When those frameworks
  #     migrate, expect a sibling helper (or a `mode:` parameter) on
  #     this module rather than forcing them through this code path.
  #   * The traversal is one level deep — we yield the directly
  #     visible files, not files reachable through their imports.
  #     Recursive resolution is the caller's job (and usually
  #     unnecessary; one level covers the controller-→-DTO case).
  module ImportGraph
    @@sibling_source_roots_cache = Hash(String, Array(String)).new
    @@sibling_source_roots_mutex = Mutex.new
    @@scanned_package_roots : Hash(String, Array(Tuple(String, String, String?)))? = nil
    @@scanned_package_roots_mutex = Mutex.new

    IMPORT_RESOLUTION_MAX_ENTRIES = 262_144
    PACKAGE_SIBLINGS_MAX_ENTRIES  =  32_768

    @@import_resolution_cache = Hash(String, Array(String)).new
    @@import_resolution_mutex = Mutex.new

    @@package_siblings_cache = Hash(String, Array(String)).new
    @@package_siblings_mutex = Mutex.new

    DIRECTORY_MAX_ENTRIES = 262_144

    @@directory_cache = Hash(String, Bool).new
    @@directory_mutex = Mutex.new

    @@dotted_dirs_cache = Hash(String, Array(String)).new
    @@dotted_dirs_mutex = Mutex.new

    # Filesystem-derived memos must not survive into a second scan of a
    # different tree in the same process (`--diff`, library use).
    Noir::ExtractionResultCache.register_clearer do
      @@sibling_source_roots_mutex.synchronize { @@sibling_source_roots_cache.clear }
      @@scanned_package_roots_mutex.synchronize { @@scanned_package_roots = nil }
      @@import_resolution_mutex.synchronize { @@import_resolution_cache.clear }
      @@package_siblings_mutex.synchronize { @@package_siblings_cache.clear }
      @@directory_mutex.synchronize { @@directory_cache.clear }
      @@dotted_dirs_mutex.synchronize { @@dotted_dirs_cache.clear }
    end

    # An import declaration extracted from a source file.
    #
    #   - `path`     dotted path written in the source
    #                (`com.example.foo.Bar`, or `com.example.foo`
    #                for wildcard imports).
    #   - `wildcard` whether the import is a `.*` form (Java/Kotlin)
    #                or equivalent `from x import *` style.
    struct ImportRef
      getter path : String
      getter? wildcard : Bool

      def initialize(@path, @wildcard)
      end
    end

    # Yields every file path that should be considered when resolving
    # symbols visible to `path`:
    #
    #   1. `path` itself.
    #   2. Same-directory siblings ending in `.{extension}` (same
    #      package).
    #   3. Files reachable through `imports`, resolved against a
    #      source root inferred from `package_name`.
    #
    # Wildcard imports expand to every matching file in the imported
    # directory. Each file is yielded at most once. When
    # `package_name` is empty, the source-root step is skipped (no
    # safe inference possible) — same-directory siblings are still
    # yielded.
    def self.related_files(path : String,
                           package_name : String,
                           imports : Indexable(ImportRef),
                           extension : String,
                           &block : String ->) : Nil
      seen = Set(String).new
      visit = ->(file : String) do
        block.call(file) if seen.add?(file)
      end

      visit.call(path)

      package_dir = File.dirname(path)
      package_siblings(package_dir, extension).each do |sibling|
        next if sibling == path
        visit.call(sibling)
      end

      return if package_name.empty?
      source_root = source_root_for(path, package_name)
      return unless source_root

      imports.each do |imp|
        resolve_import(source_root, imp, extension).each { |file| visit.call(file) }
      end
    end

    # Files an import declaration resolves to, under `source_root` and
    # its sibling module roots.
    #
    # Memoized. The resolution is a pure function of
    # `(source_root, import, extension)` — `sibling_source_roots` is
    # itself derived from `source_root` — while the inputs repeat
    # heavily: every controller in a module imports the same JDK and
    # framework classes, and each one used to re-probe
    # `1 + sibling_roots.size` paths per import. On `spring-boot`
    # (386 `src/main/java` roots) that was ~500k `access(2)` calls,
    # a quarter of the whole `java_spring` analyzer.
    private def self.resolve_import(source_root : String,
                                    imp : ImportRef,
                                    extension : String) : Array(String)
      relative = imp.path.gsub(".", "/")
      kind = imp.wildcard? ? "wildcard" : "single"
      cache_key = "#{kind} #{extension} #{source_root} #{relative}"
      @@import_resolution_mutex.synchronize do
        if cached = @@import_resolution_cache[cache_key]?
          return cached
        end
      end

      sibling_roots = sibling_source_roots(source_root)
      local_roots = [source_root] + sibling_roots
      resolved = [] of String
      # Roots holding dotted package folders (`com.example/model` for
      # `com.example.model`) try every spelling under the importing module's
      # own root, then under its siblings, before any wider root: the nearer
      # module's package wins whichever way the other one spells it.
      dotted = dotted_spellings(source_root, local_roots, imp.path)
      unless dotted.empty?
        spellings = [relative] + dotted
        [[source_root], sibling_roots].each do |roots|
          next if roots.empty?
          spellings.each do |spelling|
            resolved = resolve_spelling(roots.first, roots[1..], roots, spelling, imp.wildcard?, extension, wide: false)
            break unless resolved.empty?
          end
          break unless resolved.empty?
        end
      end
      resolved = resolve_spelling(source_root, sibling_roots, local_roots, relative, imp.wildcard?, extension) if resolved.empty?

      @@import_resolution_mutex.synchronize do
        Noir::ExtractionResultCache.store_capped(@@import_resolution_cache, cache_key, resolved, IMPORT_RESOLUTION_MAX_ENTRIES)
      end
    end

    # `dotted_path` spelled under each dotted folder directly below
    # `local_roots` that is a prefix of it.
    private def self.dotted_spellings(source_root : String, local_roots : Array(String), dotted_path : String) : Array(String)
      dotted_package_dirs(source_root, local_roots).compact_map do |folder|
        if dotted_path == folder
          folder
        elsif dotted_path.starts_with?(folder) && dotted_path[folder.size]? == '.'
          "#{folder}/#{dotted_path[(folder.size + 1)..].tr(".", "/")}"
        end
      end
    end

    # Names of the directories with a dot directly below `local_roots`.
    # Almost always none; one memoised glob per root, and the union kept
    # per source root so an import does not revisit every sibling root.
    private def self.dotted_package_dirs(source_root : String, local_roots : Array(String)) : Array(String)
      key = "\0#{source_root}" # never a path, so never a `dotted_dirs_below` key
      @@dotted_dirs_mutex.synchronize do
        if cached = @@dotted_dirs_cache[key]?
          return cached
        end
      end
      dirs = local_roots.flat_map { |root| dotted_dirs_below(root) }.uniq!
      @@dotted_dirs_mutex.synchronize { @@dotted_dirs_cache[key] = dirs }
    end

    private def self.dotted_dirs_below(root : String) : Array(String)
      @@dotted_dirs_mutex.synchronize do
        if cached = @@dotted_dirs_cache[root]?
          return cached
        end
      end
      dirs = [] of String
      safe_glob(root, "*.*") { |entry| dirs << File.basename(entry) if directory?(entry) }
      @@dotted_dirs_mutex.synchronize { @@dotted_dirs_cache[root] = dirs }
    end

    private def self.resolve_spelling(source_root : String, sibling_roots : Array(String), local_roots : Array(String),
                                      relative : String, wildcard : Bool, extension : String,
                                      wide : Bool = true) : Array(String)
      last_sep = relative.rindex('/')
      relative_dir = last_sep ? relative[0, last_sep] : ""
      resolved = [] of String
      if wildcard
        local_roots.each { |root| resolved.concat(files_in(root, relative, extension)) }
        if resolved.empty? && wide
          registered_package_roots(source_root, relative).each { |root| resolved.concat(files_in(root, relative, extension)) }
        end
      else
        # `File.exists?(root/pkg/Name.ext)` can only be true when
        # `root/pkg` is a directory, and the package directory is shared
        # by every class in that package — so the memoised directory test
        # collapses a whole package's worth of misses into one `stat`.
        # A JDK import like `java.util.List` otherwise probed every one of
        # spring-boot's sibling module roots, per importing file.
        resolved = class_files_in([source_root], relative, relative_dir, extension)
        resolved = class_files_in(sibling_roots, relative, relative_dir, extension) if resolved.empty?
        wider_roots = [] of String
        if resolved.empty? && wide
          wider_roots = registered_package_roots(source_root, relative_dir)
          resolved = class_files_in(wider_roots, relative, relative_dir, extension)
        end
        # Kotlin files may be named anything and hold many top-level
        # classes (`dto/Requests.kt` declaring `FeedRequest`), so a miss on
        # `pkg/Name.kt` falls back to the package's files, as `pkg.*` would.
        if resolved.empty? && extension == "kt" && !relative_dir.empty?
          local_roots.each { |root| resolved.concat(files_in(root, relative_dir, extension)) }
          if resolved.empty?
            wider_roots.each { |root| resolved.concat(files_in(root, relative_dir, extension)) }
          end
        end
      end
      resolved
    end

    private def self.class_files_in(roots : Array(String), relative : String,
                                    relative_dir : String, extension : String) : Array(String)
      found = [] of String
      roots.each do |root|
        next unless directory?(File.join(root, relative_dir))
        file = File.join(root, "#{relative}.#{extension}")
        found << file if File.exists?(file)
      end
      found
    end

    private def self.files_in(root : String, package_dir : String, extension : String) : Array(String)
      dir = File.join(root, package_dir)
      directory?(dir) ? package_siblings(dir, extension) : [] of String
    end

    # Same-package siblings for one directory. Every file in a package
    # asks the identical question, so one `Dir.glob` per directory
    # replaces one per file.
    private def self.package_siblings(package_dir : String, extension : String) : Array(String)
      cache_key = "#{extension} #{package_dir}"
      @@package_siblings_mutex.synchronize do
        if cached = @@package_siblings_cache[cache_key]?
          return cached
        end
      end

      siblings = [] of String
      safe_glob(package_dir, "*.#{extension}") { |sibling| siblings << sibling }

      @@package_siblings_mutex.synchronize do
        Noir::ExtractionResultCache.store_capped(@@package_siblings_cache, cache_key, siblings, PACKAGE_SIBLINGS_MAX_ENTRIES)
      end
    end

    # Memoised `Dir.exists?`. See the call site for why the directory
    # test is an exact short-circuit for the file test.
    private def self.directory?(path : String) : Bool
      @@directory_mutex.synchronize do
        if cached = @@directory_cache[path]?
          return cached
        end
      end
      exists = Dir.exists?(path)
      @@directory_mutex.synchronize do
        if @@directory_cache.size >= DIRECTORY_MAX_ENTRIES
          @@directory_cache.clear
        end
        @@directory_cache[path] = exists
      end
      exists
    end

    # Infer the source root by stripping the package path from the
    # file's directory. `src/main/java/com/foo/Bar.java` with package
    # `com.foo` returns `src/main/java`. Returns nil when the package
    # path doesn't actually trail the file's directory (the source
    # tree is laid out differently and we can't safely resolve
    # imports). javac also accepts a folder that spells several package
    # segments with dots (`src/main/java/com.example/web` for
    # `com.example.web`), so a folder may consume more than one segment.
    def self.source_root_for(file_path : String, package_name : String) : String?
      package_segments = package_name.split('.')
      dir_segments = File.dirname(file_path).split('/')
      remaining = package_segments.size
      idx = dir_segments.size
      while remaining > 0 && idx > 0
        parts = dir_segments[idx - 1].split('.')
        break if parts.empty? || parts.size > remaining
        break unless package_segments[remaining - parts.size, parts.size] == parts
        remaining -= parts.size
        idx -= 1
      end
      return unless remaining == 0
      root = dir_segments[0, idx].join('/')
      root.empty? ? "." : root
    end

    # Whether `file` is where the type `fqn` lives: `com/foo/Bar.java`, or
    # with package folders spelled with dots (`com.foo/Bar.java`).
    def self.fqn_file?(file : String, fqn : String, extension : String) : Bool
      "/#{file}".tr("/", ".").ends_with?(".#{fqn}.#{extension}")
    end

    # Gradle/Maven multi-module JVM repos often keep controllers in one
    # module and DTOs in another sibling module. If an explicit import
    # misses under the current `src/main/{java,kotlin}` root, search
    # sibling module roots with the same source-set language.
    private def self.sibling_source_roots(source_root : String) : Array(String)
      expanded = Noir::PathScope.expand(source_root)
      @@sibling_source_roots_mutex.synchronize do
        if cached = @@sibling_source_roots_cache[expanded]?
          return cached
        end
      end

      roots = [] of String
      segments = expanded.split('/')
      if segments.size >= 4
        lang = segments[-1]
        if (lang == "java" || lang == "kotlin") && segments[-2] == "main" && segments[-3] == "src"
          module_root = segments[0, segments.size - 3].join('/')
          workspace_root = File.dirname(module_root)
          safe_glob(workspace_root, "*/src/main/#{lang}") do |candidate|
            next unless Dir.exists?(candidate)
            candidate_expanded = Noir::PathScope.expand(candidate)
            roots << candidate if candidate_expanded != expanded
          end
        end
      end

      @@sibling_source_roots_mutex.synchronize do
        @@sibling_source_roots_cache[expanded] = roots
      end
      roots
    end

    # Monorepos keep shared modules at other depths than the direct
    # siblings (`shared/` next to `apps/portal`). Consulted only after the
    # local roots miss: the registered `src/main/{lang}` roots under the
    # same `-b` base that actually hold `package_dir`, an index lookup
    # rather than a probe of every module root.
    private def self.registered_package_roots(source_root : String, package_dir : String) : Array(String)
      lang = File.basename(source_root)
      entries = scanned_package_roots["#{lang}:#{package_dir}"]?
      return [] of String unless entries
      expanded = Noir::PathScope.expand(source_root)
      base = Noir::PathScope.longest_base(expanded, CodeLocator.instance.scan_base_paths)
      return [] of String unless base
      entries.compact_map { |root, root_expanded, root_base| root if root_base == base && root_expanded != expanded }
    end

    # `"{lang}:{package dir}" => [{root as registered, expanded, owning -b base}]`
    # for every scanned file under a `src/main/{java,kotlin}` root, built
    # once from the file registry. The registered spelling keeps resolved
    # files on the content cache's keys.
    private def self.scanned_package_roots : Hash(String, Array(Tuple(String, String, String?)))
      @@scanned_package_roots_mutex.synchronize do
        @@scanned_package_roots ||= begin
          bases = CodeLocator.instance.scan_base_paths
          root_info = Hash(String, Tuple(String, String, String?)).new
          index = Hash(String, Array(Tuple(String, String, String?))).new
          {".java", ".kt"}.each do |ext|
            CodeLocator.instance.files_by_extension(ext).each do |file|
              {"java", "kotlin"}.each do |lang|
                marker = "/src/main/#{lang}/"
                next unless idx = file.index(marker)
                rest = file[(idx + marker.size)..]
                next unless slash = rest.rindex('/')
                root = file[0, idx + marker.size - 1]
                info = root_info[root] ||= begin
                  expanded = Noir::PathScope.expand(root)
                  {root, expanded, Noir::PathScope.longest_base(expanded, bases)}
                end
                entries = index["#{lang}:#{rest[0, slash]}"] ||= [] of Tuple(String, String, String?)
                entries << info unless entries.includes?(info)
              end
            end
          end
          index
        end
      end
    end

    # `glob_under(dir, pattern)`, block form. `Dir.glob` raises on
    # unreadable entries in some edge cases; swallow those so one bad
    # sibling doesn't sink the whole walk.
    private def self.safe_glob(dir : String, pattern : String, &block : String ->) : Nil
      glob_under(dir, pattern).each { |p| block.call(p) }
    rescue
    end

    # ----------------------------------------------------------------
    # Relative-import resolution (JS / Ruby flavour).
    #
    # JS / Node / Ruby imports are filesystem-relative — neither the
    # JVM-style package-trailing-the-directory inference nor a
    # source-root model applies. The caller hands over the importing
    # file and the import specifier (`./foo`, `../bar/baz`,
    # `./users.js`) and we return the resolved absolute path or
    # `nil` when nothing on disk matches.
    #
    # Intended for JS analyzers (Express / Hono / Hapi cross-file
    # route discovery in particular) and any future Ruby / Lua / Lua
    # analyzer that uses `require './foo'` style paths. Bare
    # specifiers (`lodash`, `@hapi/hapi`) aren't filesystem-relative
    # — those need a `node_modules` walk that's deliberately out of
    # scope for noir today.
    #
    # Resolution order, mirroring Node's CJS algorithm:
    #
    #   1. If the specifier already carries a known extension, only
    #      that exact file is tried.
    #   2. Otherwise, `<base>/<specifier>.<ext>` for each candidate
    #      extension in priority order.
    #   3. Finally, `<base>/<specifier>/index.<ext>` for each
    #      candidate extension — the directory-with-index form.
    #
    # **Boundary enforcement.** Source files are untrusted input —
    # an attacker-controlled repo can ship `import x from
    # '../../../../etc/passwd'`, which would otherwise resolve into
    # arbitrary paths on the scanner's disk and trigger
    # `File.exists?` probes outside the scan root. Pass the project
    # root (or a parent of `from_file` you want to constrain to)
    # via `boundary:` so the helper rejects any specifier that
    # resolves outside that subtree. Callers should always pass it
    # in production; the parameter is optional only because the
    # legacy spec helpers exercise the resolver against scratch
    # tmpdirs that aren't worth boundary-wrapping.

    JS_RESOLVE_EXTENSIONS = ["ts", "tsx", "js", "jsx", "mjs", "cjs"]

    # TypeScript ESM (`moduleResolution: NodeNext`) imports a sibling `.ts`
    # source through a `.js`-family specifier — `import x from './a.js'`
    # where the file on disk is `a.ts`. Map each JS extension to the TS
    # source extension(s) it can stand in for.
    JS_TO_TS_EXT = {".js" => [".ts", ".tsx"], ".jsx" => [".tsx"], ".mjs" => [".mts"], ".cjs" => [".cts"]}

    def self.resolve_relative_import(from_file : String,
                                     import_specifier : String,
                                     extensions : Array(String) = JS_RESOLVE_EXTENSIONS,
                                     boundary : String? = nil) : String?
      resolved = resolve_relative_candidate(from_file, import_specifier, extensions, boundary)
      return unless resolved
      return resolved unless boundary
      # Second gate, on the real path this time — see `under_boundary?`.
      # Runs once per successfully resolved import (not per candidate
      # extension), so it costs a pair of `realpath` calls on a path that
      # already paid for several `File.exists?` probes.
      real_under_boundary?(resolved, boundary) ? resolved : nil
    end

    private def self.resolve_relative_candidate(from_file : String,
                                                import_specifier : String,
                                                extensions : Array(String),
                                                boundary : String?) : String?
      return unless import_specifier.starts_with?("./") || import_specifier.starts_with?("../")

      base_dir = File.dirname(from_file)
      combined = Noir::PathScope.expand(File.join(base_dir, import_specifier))

      # Boundary check — drop the resolution before any disk I/O so
      # we don't even fingerprint files outside the scan root.
      if boundary
        return unless under_boundary?(combined, boundary)
      end

      # Specifier with an explicit extension — that exact path or
      # nothing. Mirrors Node's behaviour for fully-qualified
      # `./foo.ts` imports.
      if extensions.any? { |ext| import_specifier.ends_with?(".#{ext}") }
        return combined if File.exists?(combined)

        # TS ESM fallback: a `.js`-family specifier resolves to the
        # sibling `.ts` source when the literal `.js` file is absent.
        # Without this, cross-file route discovery in every modern TS
        # project (which compiles to ESM and imports `./x.js`) silently
        # fails to follow the import.
        JS_TO_TS_EXT.each do |js_ext, ts_exts|
          next unless import_specifier.ends_with?(js_ext)
          base = combined[0...(combined.size - js_ext.size)]
          ts_exts.each do |ts_ext|
            candidate = "#{base}#{ts_ext}"
            return candidate if File.exists?(candidate)
          end
        end
        return
      end

      extensions.each do |ext|
        candidate = "#{combined}.#{ext}"
        return candidate if File.exists?(candidate)
      end

      if Dir.exists?(combined)
        extensions.each do |ext|
          candidate = File.join(combined, "index.#{ext}")
          return candidate if File.exists?(candidate)
        end
      end

      nil
    end

    # `combined` is already an absolute, lexically-normalised path
    # (post `File.expand_path`). Boundary likewise gets expanded so
    # the comparison works even when callers hand over a relative
    # `./project` form.
    #
    # The check is purely lexical — symlinks aren't followed, so
    # `<boundary>/foo -> /etc/passwd` passes it. That is not a
    # pre-existing-symlink-on-the-scanner's-disk scenario as once assumed:
    # git tracks symlinks, absolute target and all, so the hostile checkout
    # brings its own. Followed outside the boundary, the target gets parsed
    # as source and can surface in `code_paths` or a passive-scan extract.
    #
    # This stays as the cheap first gate — it rejects `../../etc/passwd`
    # before any disk I/O, which is what the caller wants — and
    # `real_under_boundary?` re-checks the resolved path once the disk has
    # confirmed it exists.
    private def self.under_boundary?(combined : String, boundary : String) : Bool
      # `File.expand_path` does NOT strip a trailing separator in Crystal, so
      # a caller passing `-b project/` would yield `boundary_abs` ending in
      # `/`, making the `boundary_abs + SEPARATOR` prefix a `//` that no real
      # path starts with — every import would be (wrongly) rejected as
      # out-of-boundary. Chomp the trailing separator so the check is robust
      # to both `project` and `project/` forms.
      boundary_abs = Noir::PathScope.expand(boundary).chomp('/')
      combined == boundary_abs || combined.starts_with?(boundary_abs + "/")
    end

    # Containment of the symlink-resolved path. Both sides are resolved, so a
    # boundary that is itself reached through a link (`/tmp` -> `/private/tmp`
    # on macOS) still matches its own contents. An unresolvable path — a
    # dangling link, a directory we can't traverse — is treated as outside.
    private def self.real_under_boundary?(resolved : String, boundary : String) : Bool
      real_path = File.realpath(resolved)
      real_boundary = File.realpath(boundary).chomp(File::SEPARATOR)
      real_path == real_boundary || real_path.starts_with?(real_boundary + File::SEPARATOR)
    rescue File::Error
      false
    end
  end
end

# ----------------------------------------------------------------
# Python flavour.
#
# Python imports are dotted-module paths anchored at one of:
#
#   1. `app_base_path` — the project's source root (the `app`
#      directory passed by the analyzer).
#   2. The current file's directory, for relative imports
#      (`from . import x`, `from .. import x`).
#
# The resolver walks the dotted path one segment at a time,
# preferring directories (Python packages) over file siblings
# (modules) until either a leaf `.py` is found or the path runs
# out — matching the behaviour expected by the existing
# Django / FastAPI / Tornado analyzers.
#
# Lives under the shared `Noir::ImportGraph` umbrella so a future
# Python analyzer migration off the legacy `PythonParser` (still
# used by Flask) can reuse the same resolver. Until that
# migration lands the JVM / JS / Python flavours all share the
# top-level module but each operates on its own data shapes —
# Python's hashes look different from the JVM `ImportRef` form
# because Python returns import-name → file-path mappings rather
# than a yield of files.
module Noir::ImportGraph::Python
  module PackageType
    FILE = 0
    CODE = 1
  end

  # Find every `import` and `from … import …` line in `content`
  # and resolve each name to a `{filepath, package_type}` tuple.
  # Returns an empty hash for files that import nothing
  # resolvable. The map is keyed on the IMPORTED-IN-LOCAL name —
  # `from a.b import c as d` keys `d`, not `c`.
  #
  # `app_base_path` anchors the dotted path for absolute imports;
  # `file_path`'s directory anchors relative imports. Pass
  # `content` when the caller already has the file in hand to
  # skip the second disk read.
  def self.find_imported_modules(app_base_path : String,
                                 file_path : String,
                                 content : String? = nil) : Hash(String, Tuple(String, Int32))
    content = Noir::TextFile.read(file_path) if content.nil?

    file_base_path = file_path
    file_base_path = File.dirname(file_path) if file_path.ends_with? ".py"

    import_map = Hash(String, Tuple(String, Int32)).new
    each_import_statement(content) do |from_import, names|
      add_python_imports(import_map, app_base_path, file_base_path, from_import, names)
    end
    import_map
  end

  # Map each name an import binds to `{declaring file, original name}`.
  # `from pkg.mod import bp as users_bp` keys `users_bp` to
  # `{pkg/mod.py, "bp"}`, so a caller can find the object where it was
  # declared, under the name it was declared with. A name that binds a
  # module (`from . import views`, `import shop.urls`) maps to that
  # module's file (`__init__.py` for a package) with an empty original
  # name; a plain `import a.b` is keyed on the whole dotted `a.b`.
  def self.find_imported_symbols(app_base_path : String,
                                 file_path : String,
                                 content : String? = nil) : Hash(String, Tuple(String, String))
    content = Noir::TextFile.read(file_path) if content.nil?
    file_dir = file_path.ends_with?(".py") ? File.dirname(file_path) : file_path

    symbols = Hash(String, Tuple(String, String)).new
    each_import_statement(content) do |from_import, names|
      package_path = app_base_path
      module_dotted = from_import
      if from_import.starts_with?(".")
        dots = from_import.size - from_import.lstrip('.').size
        package_path = file_dir
        (dots - 1).times { package_path = File.dirname(package_path) }
        module_dotted = from_import[dots..]
      end

      names.split(",").each do |spec|
        name, _, alias_name = spec.strip.partition(/\s+as\s+/)
        next if name.empty? || name == "*"
        local = alias_name.empty? ? name : alias_name.strip
        if from_import.empty?
          file = resolve_module_file(package_path, name)
          symbols[local] = {file, ""} if file
        elsif file = resolve_module_file(package_path, module_dotted.empty? ? name : "#{module_dotted}.#{name}")
          symbols[local] = {file, ""}
        elsif file = resolve_module_file(package_path, module_dotted)
          symbols[local] = {file, name}
        end
      end
    end
    symbols
  end

  # The `.py` file a dotted module path names under `package_path`: the
  # leaf module, or the package's `__init__.py`. An empty path names the
  # `package_path` package itself.
  private def self.resolve_module_file(package_path : String, dotted : String) : String?
    dir = package_path
    segments = dotted.empty? ? [] of String : dotted.split(".")
    segments.each_with_index do |segment, index|
      candidate = File.join(dir, segment)
      if index == segments.size - 1 && File.file?("#{candidate}.py") && exact_entry?(dir, "#{segment}.py")
        return "#{candidate}.py"
      elsif File.directory?(candidate) && exact_entry?(dir, segment)
        dir = candidate
      else
        return
      end
    end
    init = File.join(dir, "__init__.py")
    File.file?(init) ? init : nil
  end

  # Python matches module names case-sensitively; a case-insensitive file
  # system (macOS, Windows) would otherwise let `from .models import
  # Order` bind the module `order.py` instead of the re-exported class.
  @@dir_entries = Hash(String, Set(String)).new
  @@dir_entries_mutex = Mutex.new

  private def self.exact_entry?(dir : String, name : String) : Bool
    entries = @@dir_entries_mutex.synchronize { @@dir_entries[dir]? }
    unless entries
      entries = begin
        Dir.children(dir).to_set
      rescue File::Error
        Set(String).new
      end
      @@dir_entries_mutex.synchronize { @@dir_entries[dir] = entries }
    end
    entries.includes?(name)
  end

  # Yield every `import` / `from … import …` statement as `{from part,
  # comma-separated names}` (the from part is empty for a plain
  # `import`). Indented imports count too: an app factory routinely
  # imports its blueprints inside `create_app()`.
  private def self.each_import_statement(content : String, &) : Nil
    # A parenthesised import still waiting for its `)`: the `from` part
    # and the names collected so far. Collected per line with comments
    # cut first, so neither a `(`/`)` in a `#` comment nor a CRLF
    # terminator can shift where the name list starts or stops.
    open_from : String? = nil
    open_names = String::Builder.new
    content.each_line do |raw_line|
      if from = open_from
        code = strip_import_comment(raw_line)
        if close = code.index(')')
          open_names << code[0, close]
          yield from, open_names.to_s
          open_from = nil
        else
          open_names << code << '\n'
        end
        next
      end

      line = raw_line.lstrip
      from_import = ""
      imports = ""

      if line.starts_with?("from")
        line.scan(/from\s*([^'"\s\\]*)\s*import\s*(.*)/) do |match|
          next if match.size != 3
          from_import = match[1]
          imports = match[2]
        end
      elsif line.starts_with?("import")
        line.scan(/import\s*([^'"\s\\]*)/) do |match|
          next if match.size != 2
          imports = match[1]
        end
      end

      unless imports.empty?
        code = strip_import_comment(imports)
        if open = code.index('(')
          rest = code[(open + 1)..]
          if close = rest.index(')')
            yield from_import, rest[0, close]
          else
            open_from = from_import
            open_names = String::Builder.new
            open_names << rest << '\n'
          end
        else
          yield from_import, code
        end
      end
    end
  end

  # `line` up to its first `#`. Import statements carry no string
  # literals, so the first `#` always starts a comment.
  private def self.strip_import_comment(line : String) : String
    (hash = line.index('#')) ? line[0, hash] : line
  end

  # Resolve the comma-separated names of one import statement into
  # `import_map`. `from_import` is the dotted module after `from`
  # (empty for a plain `import`).
  private def self.add_python_imports(import_map : Hash(String, Tuple(String, Int32)),
                                      app_base_path : String,
                                      file_base_path : String,
                                      from_import : String,
                                      imports : String) : Nil
    package_path = app_base_path
    # `..` resolves to file's parent dir; `.` to file's dir. The parent is
    # taken lexically, not as `dir/..`: the resolved path is compared with
    # the scanned file paths, which never spell `..`.
    if from_import.starts_with?("..")
      package_path = File.dirname(file_base_path)
      from_import = from_import[2..]
    elsif from_import.starts_with?(".")
      package_path = file_base_path
      from_import = from_import[1..]
    end

    imports.split(",").each do |import|
      import = import.strip
      if import.starts_with?("..")
        package_path = File.dirname(file_base_path)
      elsif import.starts_with?(".")
        package_path = file_base_path
      end

      dotted_as_names = import
      dotted_as_names = "#{from_import}.#{import}" unless from_import.empty?

      import_package_map = find_imported_package(package_path, dotted_as_names)
      next if import_package_map.empty?
      import_package_map.each do |name, filepath, package_type|
        import_map[name] = {filepath, package_type}
      end
    end
  end

  # Resolve a dotted Python identifier (`a.b.c` or
  # `a.b.c, d.e as f`) under `package_path`. Walks segment by
  # segment, preferring packages (directories) over modules
  # (`.py` files). Returns each resolvable name as `{name,
  # filepath, package_type}` so the caller can keep the alias
  # mapping intact.
  def self.find_imported_package(package_path : String,
                                 dotted_as_names : String) : Array(Tuple(String, String, Int32))
    package_map = Array(Tuple(String, String, Int32)).new

    py_path = ""
    is_positive_travel = false
    alias_name = nil
    import_path = dotted_as_names.strip
    if import_path.includes?(" as ")
      import_path, alias_name = import_path.split(/\s+as\s+/, 2)
      import_path = import_path.strip
      alias_name = alias_name.strip
    end

    dotted_as_names_split = import_path.split(".")

    dotted_as_names_split.each_with_index do |segment, index|
      # The final segment can carry an `… as alias` suffix
      # (`from pkg import module as alias`). Strip it before building
      # the filesystem path, otherwise `pkg/module as alias.py` never
      # matches and the import silently resolves to an empty path —
      # which broke every `from .articles import api as articles`
      # style module-alias re-export (seen on fastapi-realworld).
      names = segment.includes?(" as ") ? segment.split(" as ", 2)[0].strip : segment
      travel_package_path = File.join(package_path, names)

      py_guess = "#{travel_package_path}.py"
      if File.directory?(travel_package_path)
        package_path = travel_package_path
        is_positive_travel = true
      elsif dotted_as_names_split.size - 2 <= index && File.exists?(py_guess)
        py_path = py_guess
        is_positive_travel = true
      else
        break
      end
    end

    if is_positive_travel
      names = dotted_as_names_split[-1]
      names.split(",").each do |name|
        import = name.strip
        next if import.empty?

        if import.includes?(" as ")
          import, alias_name = import.split(" as ")
        end

        package_type = File.exists?(File.join(package_path, "#{import}.py")) ? PackageType::FILE : PackageType::CODE

        if alias_name.nil?
          package_map << {import, py_path, package_type}
        else
          package_map << {alias_name, py_path, package_type}
        end
      end
    end

    package_map
  end
end
