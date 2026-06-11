require "../../models/analyzer"
require "../../miniparsers/js_callee_extractor"

module Analyzer::Javascript
  abstract class JavascriptEngine < Analyzer
    # Default extension set for JavaScript/TypeScript source files.
    # Analyzers with a different filter (e.g. Nitro adds `.mts`, NestJS JS
    # only uses `.js`/`.jsx`) pass their own list to `parallel_file_scan`.
    DEFAULT_EXTENSIONS      = [".js", ".ts", ".jsx", ".tsx"]
    JS_PROJECT_ROOT_MARKERS = [
      "package.json",
      "next.config.js", "next.config.ts", "next.config.mjs", "next.config.cjs",
      "svelte.config.js", "svelte.config.ts", "svelte.config.mjs", "svelte.config.cjs",
    ]

    # Walk the project tree concurrently, invoking the block for each
    # readable source file whose extension matches. JS/TS analyzers vary
    # in the exact filter (plain JS vs TS vs .mjs vs .tsx), so the filter
    # is an argument with a sensible default.
    #
    # Name-consistent with the other engines' `parallel_file_scan` helpers.
    protected def parallel_file_scan(extensions : Array(String) = DEFAULT_EXTENSIONS, &block : String -> Nil) : Nil
      begin
        parallel_analyze(all_files) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next unless extensions.any? { |ext| path.ends_with?(ext) }

          begin
            block.call(path)
          rescue e
            logger.debug "Error analyzing #{path}: #{e}"
          end
        end
      rescue e
        logger.debug e
      end
    end

    # Crystal recompiles an interpolated regex literal (/...#{x}.../) on
    # every evaluation — a full PCRE2 JIT compile. Patterns keyed by a
    # discovered name ("req", "query", "body", router vars, ...) are
    # low-cardinality across a scan, so memoize them per analyzer
    # instance. Fibers are cooperative (no preview_mt), so the plain
    # Hash is safe under parallel_file_scan.
    @dynamic_regex_cache = Hash(String, Regex).new

    protected def cached_regex(key : String, & : -> Regex) : Regex
      @dynamic_regex_cache.fetch(key) do
        @dynamic_regex_cache[key] = yield
      end
    end

    protected def attach_js_callees(endpoint : Endpoint, callees : Array(Noir::JSCalleeExtractor::Entry))
      callees.each do |name, callee_path, line|
        endpoint.push_callee(Callee.new(name, path: callee_path, line: line))
      end
    end

    protected def javascript_source_language(path : String) : Symbol
      path.ends_with?(".ts") || path.ends_with?(".mts") || path.ends_with?(".tsx") ? :typescript : :javascript
    end

    protected def collect_static_paths(source_path : String, content : String, static_dirs : Array(Hash(String, String)), framework : Symbol? = nil) : Nil
      Noir::JSRouteExtractor.extract_static_paths(content, framework).each do |static_path|
        normalized = static_path.dup
        normalized["file_path"] = resolve_static_file_path(source_path, normalized["file_path"])
        static_dirs << normalized unless static_dirs.any? { |s| s["static_path"] == normalized["static_path"] && s["file_path"] == normalized["file_path"] }
      end
    end

    protected def process_js_static_dirs(static_dirs : Array(Hash(String, String)), result : Array(Endpoint)) : Nil
      expanded_files = nil.as(Array(Tuple(String, String))?)

      static_dirs.each do |dir|
        root = Noir::PathScope.normalize_root(dir["file_path"])
        static_path = dir["static_path"]
        static_path = static_path[0..-2] if static_path.ends_with?("/") && static_path != "/"

        files = expanded_files ||= all_files.compact_map do |file_path|
          next if File.directory?(file_path)
          {file_path, File.expand_path(file_path)}
        end

        files.each do |file_path, expanded_file_path|
          next unless Noir::PathScope.under_normalized_root?(expanded_file_path, root)

          relative_path = expanded_file_path[root.size..]?.try(&.lchop(File::SEPARATOR)) || ""
          next if relative_path.empty?

          url = if static_path == "/" || static_path.empty?
                  "/#{relative_path}"
                else
                  "#{static_path}/#{relative_path}"
                end
          url = url.gsub_repeatedly("//", "/")

          details = Details.new(PathInfo.new(file_path))
          endpoint = Endpoint.new(url, "GET", details)
          result << endpoint unless result.any? { |e| e.url == url && e.method == "GET" }
        end
      end
    end

    protected def discover_js_project_roots(package_markers : Array(String), config_basenames : Array(String)) : Array(String)
      roots = [] of String

      all_files.each do |file|
        base = File.basename(file)
        if config_basenames.includes?(base)
          add_project_root(roots, File.dirname(file))
        elsif base == "package.json"
          begin
            content = read_file_content(file)
          rescue File::NotFoundError
            next
          end
          add_project_root(roots, File.dirname(file)) if package_markers.any? { |marker| content.includes?(marker) }
        end
      end

      roots
    end

    protected def path_under_project_roots?(path : String, roots : Array(String)) : Bool
      return true if roots.empty?

      expanded = File.expand_path(path)
      roots.any? do |root|
        Noir::PathScope.under_normalized_root?(expanded, root)
      end
    end

    private def resolve_static_file_path(source_path : String, raw_path : String) : String
      normalized = raw_path.strip.gsub("\\", "/")
      return File.expand_path(normalized) if normalized.starts_with?("/")

      source_dir = File.dirname(File.expand_path(source_path))
      candidates = [] of String
      candidates << File.expand_path(normalized, source_dir)

      if project_root = nearest_js_project_root(source_dir)
        candidates << File.expand_path(normalized, project_root)
      end

      @base_paths.each do |base|
        candidates << File.expand_path(normalized, base)
      end

      candidates.uniq!
      candidates.find { |candidate| Dir.exists?(candidate) || File.exists?(candidate) } || candidates.first
    end

    private def nearest_js_project_root(start_dir : String) : String?
      dir = File.expand_path(start_dir)
      bases = @base_paths.map do |base|
        expanded_base = File.expand_path(base)
        expanded_base == File::SEPARATOR ? expanded_base : expanded_base.rstrip('/')
      end

      loop do
        return dir if JS_PROJECT_ROOT_MARKERS.any? { |marker| File.exists?(File.join(dir, marker)) }
        break if bases.includes?(dir)

        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end

      nil
    end

    private def add_project_root(roots : Array(String), root : String) : Nil
      expanded = File.expand_path(root)
      expanded = expanded.rstrip('/') unless expanded == File::SEPARATOR
      roots << expanded unless roots.includes?(expanded)
    end
  end
end
