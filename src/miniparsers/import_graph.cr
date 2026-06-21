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
      safe_glob("#{package_dir}/*.#{extension}") do |sibling|
        next if sibling == path
        visit.call(sibling)
      end

      return if package_name.empty?
      source_root = source_root_for(path, package_name)
      return unless source_root
      sibling_roots = sibling_source_roots(source_root)

      imports.each do |imp|
        relative = imp.path.gsub(".", "/")
        if imp.wildcard?
          ([source_root] + sibling_roots).each do |root|
            dir = File.join(root, relative)
            next unless Dir.exists?(dir)
            safe_glob("#{dir}/*.#{extension}") { |match| visit.call(match) }
          end
        else
          file = File.join(source_root, "#{relative}.#{extension}")
          if File.exists?(file)
            visit.call(file)
          else
            sibling_roots.each do |root|
              sibling_file = File.join(root, "#{relative}.#{extension}")
              visit.call(sibling_file) if File.exists?(sibling_file)
            end
          end
        end
      end
    end

    # Infer the source root by stripping the package path from the
    # file's directory. `src/main/java/com/foo/Bar.java` with package
    # `com.foo` returns `src/main/java`. Returns nil when the package
    # path doesn't actually trail the file's directory (the source
    # tree is laid out differently and we can't safely resolve
    # imports).
    def self.source_root_for(file_path : String, package_name : String) : String?
      package_segments = package_name.split('.')
      dir = File.dirname(file_path)
      dir_segments = dir.split('/')
      return if dir_segments.size < package_segments.size
      tail = dir_segments[(dir_segments.size - package_segments.size)..]
      return unless tail == package_segments
      root = dir_segments[0, dir_segments.size - package_segments.size].join('/')
      root.empty? ? "." : root
    end

    # Gradle/Maven multi-module JVM repos often keep controllers in one
    # module and DTOs in another sibling module. If an explicit import
    # misses under the current `src/main/{java,kotlin}` root, search
    # sibling module roots with the same source-set language.
    private def self.sibling_source_roots(source_root : String) : Array(String)
      expanded = File.expand_path(source_root)
      @@sibling_source_roots_mutex.synchronize do
        if cached = @@sibling_source_roots_cache[expanded]?
          return cached
        end
      end

      roots = [] of String
      segments = expanded.split(File::SEPARATOR)
      if segments.size >= 4
        lang = segments[-1]
        if (lang == "java" || lang == "kotlin") && segments[-2] == "main" && segments[-3] == "src"
          module_root = segments[0, segments.size - 3].join(File::SEPARATOR)
          workspace_root = File.dirname(module_root)
          safe_glob(File.join(workspace_root, "*", "src", "main", lang)) do |candidate|
            next unless Dir.exists?(candidate)
            candidate_expanded = File.expand_path(candidate)
            roots << candidate if candidate_expanded != expanded
          end
        end
      end

      @@sibling_source_roots_mutex.synchronize do
        @@sibling_source_roots_cache[expanded] = roots
      end
      roots
    end

    # `Dir.glob` raises on unreadable entries in some edge cases;
    # swallow those so one bad sibling doesn't sink the whole walk.
    private def self.safe_glob(pattern : String, &block : String ->) : Nil
      Dir.glob(pattern) { |p| block.call(p) }
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
      return unless import_specifier.starts_with?("./") || import_specifier.starts_with?("../")

      base_dir = File.dirname(from_file)
      combined = File.expand_path(File.join(base_dir, import_specifier))

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
    # The check is purely lexical — symlinks aren't followed. A
    # `<boundary>/foo -> /etc` symlink could still leak; defense in
    # depth on top of this would call `File.realpath` after a
    # successful `File.exists?` and compare the realpath. Skipped
    # for now because the symlink scenario requires both an
    # attacker-controlled checkout and pre-existing symlinks on the
    # scanner's disk pointing at sensitive paths.
    private def self.under_boundary?(combined : String, boundary : String) : Bool
      # `File.expand_path` does NOT strip a trailing separator in Crystal, so
      # a caller passing `-b project/` would yield `boundary_abs` ending in
      # `/`, making the `boundary_abs + SEPARATOR` prefix a `//` that no real
      # path starts with — every import would be (wrongly) rejected as
      # out-of-boundary. Chomp the trailing separator so the check is robust
      # to both `project` and `project/` forms.
      boundary_abs = File.expand_path(boundary).chomp(File::SEPARATOR)
      combined == boundary_abs || combined.starts_with?(boundary_abs + File::SEPARATOR)
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
  # skip the second `File.read`.
  def self.find_imported_modules(app_base_path : String,
                                 file_path : String,
                                 content : String? = nil) : Hash(String, Tuple(String, Int32))
    content = File.read(file_path, encoding: "utf-8", invalid: :skip) if content.nil?

    file_base_path = file_path
    file_base_path = File.dirname(file_path) if file_path.ends_with? ".py"

    import_map = Hash(String, Tuple(String, Int32)).new
    offset = 0
    content.each_line do |line|
      package_path = app_base_path
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
        round_bracket_index = line.index('(')
        unless round_bracket_index.nil?
          # Parse `import (\n a,\n b,\n c)` pattern — track
          # bytes from the opening `(` to the matching `)`.
          index = offset + round_bracket_index + 1
          # Single index() call instead of an O(n^2) per-char walk over the
          # remaining file (String#[](Int) is O(n) on multi-byte content).
          index = content.index(')', index) || content.size
          imports = content[(offset + round_bracket_index + 1)..(index - 1)].strip
        end

        # Drop inline comments (`from x import y  # noqa: F401`,
        # `from . import (\n a,  # used by Z\n b)`). Left in place the
        # `#…` text became part of the last imported name/alias and
        # corrupted resolution. Stripping per-line (up to the newline)
        # keeps the multi-line parenthesised form intact; import
        # statements never carry a legitimate `#` outside a comment.
        imports = imports.gsub(/#[^\n]*/, "")

        # `..` resolves to file's parent dir; `.` to file's dir.
        if from_import.starts_with?("..")
          package_path = File.join(file_base_path, "..")
          from_import = from_import[2..]
        elsif from_import.starts_with?(".")
          package_path = file_base_path
          from_import = from_import[1..]
        end

        imports.split(",").each do |import|
          import = import.strip
          if import.starts_with?("..")
            package_path = File.join(file_base_path, "..")
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

      offset += line.size + 1
    end

    import_map
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

        if !alias_name.nil?
          package_map << {alias_name, py_path, package_type}
        else
          package_map << {import, py_path, package_type}
        end
      end
    end

    package_map
  end
end
