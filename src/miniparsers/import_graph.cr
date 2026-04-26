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

      imports.each do |imp|
        relative = imp.path.gsub(".", "/")
        if imp.wildcard?
          dir = File.join(source_root, relative)
          next unless Dir.exists?(dir)
          safe_glob("#{dir}/*.#{extension}") { |match| visit.call(match) }
        else
          file = File.join(source_root, "#{relative}.#{extension}")
          visit.call(file) if File.exists?(file)
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
        return File.exists?(combined) ? combined : nil
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
      boundary_abs = File.expand_path(boundary)
      combined == boundary_abs || combined.starts_with?(boundary_abs + File::SEPARATOR)
    end

    # ----------------------------------------------------------------
    # Python flavour (placeholder).
    #
    # Python frameworks (Flask, FastAPI, Sanic, Tornado) currently
    # use the regex-driven `find_imported_modules` helper inside
    # `src/analyzer/engines/python_engine.cr`. It already handles
    # the common shapes — `from foo.bar import baz`, relative `from
    # . import x` and `from .. import x`, plus parenthesised
    # multi-line imports.
    #
    # When we migrate Python analyzers off the legacy parser this
    # logic should move into a `Noir::ImportGraph` Python helper so
    # FastAPI / Sanic / Tornado cross-file route discovery can share
    # it instead of each analyzer rolling its own. Tracking that
    # under the same #1107 umbrella as the JS half above.
  end
end
