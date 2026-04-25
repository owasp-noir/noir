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
  end
end
