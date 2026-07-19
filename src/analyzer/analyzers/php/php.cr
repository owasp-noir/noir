require "../../engines/php_engine"

module Analyzer::Php
  class Php < PhpEngine
    # Precompiled once at load. The per-line gate below used to be
    # `allow_patterns.any? { |pattern| line.includes? pattern }` — 7
    # `String#includes?` scans of the line per pattern. Crystal's
    # `String#includes?` is measurably slower than a single precompiled
    # `Regex#matches?` call, and this runs on every line of every `.php`
    # file in the project, so the union regex is a straight win.
    ALLOW_PATTERNS_RE = Regex.union(["$_GET", "$_POST", "$_REQUEST", "$_SERVER", "$_COOKIE", "$_FILES", "filter_input"])

    # Directory names that conventionally hold the document root. A
    # directory only counts as one when it *also* contains an
    # `index.php` front controller — that requirement is what keeps this
    # safe: a static-site build output like `docs/public/` ships
    # `index.html`, never `index.php`, so it is not mistaken for a web
    # root. (See the warning in `Analyzer#web_root_path` about bare
    # `public/` / `www/` markers.)
    WEBROOT_DIR_NAMES = ["public", "webroot", "public_html", "htdocs", "www", "web"]

    # Per document root: {expanded web root, normalized web root}.
    # Lazily built; fibers are cooperative and nothing here yields, so a
    # plain memo is safe under `parallel_file_scan`.
    @php_web_roots : Array(Tuple(String, String))? = nil
    # Normalized roots of composer-managed projects.
    @php_managed_roots : Array(String)? = nil

    # Document roots discovered in this scan.
    #
    # Framework layouts (Laravel, Slim → `public/`; CakePHP → `webroot/`)
    # serve exactly one directory; everything else — controllers, config,
    # `bootstrap/`, `bin/` — is on disk but not addressable over HTTP.
    # Emitting those as endpoints invents attack surface that does not
    # exist, which is why they used to be suppressed wholesale by dropping
    # this analyzer whenever a framework was present.
    #
    # Returning an empty list means "no dedicated document root", which is
    # the correct reading for WordPress and for plain-PHP trees: there the
    # repository root *is* the web root, so every `.php` really is
    # reachable and the caller keeps the base-relative behaviour.
    private def php_web_roots : Array(Tuple(String, String))
      cached = @php_web_roots
      return cached if cached

      roots = [] of Tuple(String, String)
      get_files_by_extension(".php").each do |file|
        next unless File.basename(file) == "index.php"

        dir = File.dirname(file)
        next unless WEBROOT_DIR_NAMES.includes?(File.basename(dir).downcase)

        expanded = File.expand_path(dir)
        next if roots.any? { |existing, _| existing == expanded }
        roots << {expanded, Noir::PathScope.normalize_root(expanded)}
      end

      @php_web_roots = roots
      roots
    end

    # Roots of composer-managed projects. A `composer.json` means the tree
    # is an application or library with a defined entry point, not a
    # directory of directly-served scripts.
    private def php_managed_roots : Array(String)
      cached = @php_managed_roots
      return cached if cached

      roots = [] of String
      all_files.each do |file|
        next unless File.basename(file) == "composer.json"
        normalized = Noir::PathScope.normalize_root(File.dirname(file))
        roots << normalized unless roots.includes?(normalized)
      end

      @php_managed_roots = roots
      roots
    end

    # URL base for `path`, or nil when the file is not web-servable.
    #
    # Three layouts, decided per file so a monorepo can hold all of them:
    #
    #   1. Under a document root (`public/`, `webroot/`, …) — servable;
    #      the URL is relative to that root. This is what keeps a legacy
    #      `public/upload.php` visible next to a Laravel app.
    #   2. Inside a composer-managed project but outside its document
    #      root — not servable. Controllers, `config/`, `bootstrap/` and
    #      `vendor/` live on disk but are never addressable, and emitting
    #      them invents attack surface. This is the noise that used to be
    #      suppressed by dropping the whole analyzer.
    #   3. Neither — the directory *is* the document root. WordPress and
    #      plain-PHP trees serve every `.php` where it sits, so the
    #      original base-relative behaviour is correct and preserved.
    # Returns {base, path} to hand to `get_relative_path`, or nil.
    #
    # Both elements must be in the same shape. Document roots are stored
    # expanded (they are discovered via `File.expand_path`), while `path`
    # arrives however the scan base was given — relative for `-b spec/...`.
    # Mixing the two silently fails to strip the prefix and emits the whole
    # path as the URL, so the doc-root branch pairs the expanded root with
    # the expanded path, and the fallback keeps both as-given.
    private def php_url_base_for(path : String) : Tuple(String, String)?
      expanded = File.expand_path(path)

      if inside = php_web_roots.find { |_, web_root| Noir::PathScope.under_normalized_root?(expanded, web_root) }
        return {inside[0], expanded}
      end

      return if php_managed_roots.any? { |root| Noir::PathScope.under_normalized_root?(expanded, root) }

      {php_base_path_for(path), path}
    end

    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless File.extname(path) == ".php"

      resolved = php_url_base_for(path)
      return [] of Endpoint unless resolved
      url_base, url_path = resolved

      endpoints = [] of Endpoint
      relative_path = get_relative_path(url_base, url_path)
      include_callee = callees_needed?

      content = read_file_content(path)
      params_query = [] of Param
      params_body = [] of Param
      methods = [] of String

      # Pure-PHP still emits a GET pseudo-endpoint per file even when no
      # superglobals are present. Only the per-line param walk is gated.
      if content.includes?("$_") || content.includes?("filter_input")
        content.each_line do |line|
          if line.matches?(ALLOW_PATTERNS_RE)
            superglobal_matches = line.scan(/\$_(GET|POST|REQUEST|SERVER|COOKIE|FILES)\s*\[\s*['"]([^'"]+)['"]\s*\]/)
            superglobal_matches.each do |match|
              apply_param_reference(match[1], match[2], params_query, params_body, methods)
            end

            filter_input_matches = line.scan(/filter_input\s*\(\s*INPUT_(GET|POST|REQUEST|SERVER|COOKIE)\s*,\s*['"]([^'"]+)['"]/)
            filter_input_matches.each do |match|
              apply_param_reference(match[1], match[2], params_query, params_body, methods)
            end
          end
        rescue
          next
        end
      end

      # For the pure-PHP analyzer we are parameter-driven (not route-driven).
      # A file with thousands of superglobal references (e.g. a large controller
      # with many action methods) used to produce thousands of near-identical
      # Endpoint objects for the same pseudo-path. The optimizer would later
      # collapse them by (method, url) while merging params. Creating the
      # duplicates up-front was extremely expensive on large files.
      #
      # We emit at most the POST pseudo-endpoint (when any POST/REQUEST/FILES
      # reference was seen) plus the always-present GET pseudo-endpoint (for
      # query/cookie/header params discovered in the file). We also deduplicate
      # params by (name, param_type) in first-seen order so that the Endpoint
      # objects we hand to later stages carry the same logical set that the
      # optimizer would have produced. This is semantically identical to the
      # previous behaviour for all observable outputs and test expectations,
      # but avoids the O(N) explosion in intermediate objects.
      #
      # Note: unlike real framework analyzers, this one only ever contributes
      # "POST" (or nothing) to the methods list; the GET is emitted separately.
      # The wording is intentionally specific to avoid implying full multi-verb
      # route support here.
      distinct_methods = methods.uniq
      query_params = unique_params_preserve_order(params_query)
      body_params = unique_params_preserve_order(params_body)

      details = Details.new(PathInfo.new(path))
      distinct_methods.each do |method|
        endpoints << Endpoint.new("/#{relative_path}", method, body_params, details)
      end
      endpoints << Endpoint.new("/#{relative_path}", "GET", query_params, details)
      attach_file_callees(endpoints, content, path) if include_callee

      endpoints
    end

    private def apply_param_reference(method : String,
                                      param_name : String,
                                      params_query : Array(Param),
                                      params_body : Array(Param),
                                      methods : Array(String))
      if method == "GET"
        params_query << Param.new(param_name, "", "query")
      elsif method == "POST"
        params_body << Param.new(param_name, "", "form")
        methods << "POST"
      elsif method == "REQUEST"
        params_query << Param.new(param_name, "", "query")
        params_body << Param.new(param_name, "", "form")
        methods << "POST"
      elsif method == "SERVER"
        if param_name.includes? "HTTP_"
          header_name = param_name.sub("HTTP_", "").gsub("_", "-")
          params_query << Param.new(header_name, "", "header")
          params_body << Param.new(header_name, "", "header")
        end
      elsif method == "COOKIE"
        params_query << Param.new(param_name, "", "cookie")
        params_body << Param.new(param_name, "", "cookie")
      elsif method == "FILES"
        params_body << Param.new(param_name, "", "file")
        methods << "POST"
      end
    end

    # Order-preserving dedup of params by (name, param_type).
    # The pure-PHP analyzer accumulates every superglobal reference it sees.
    # For files with repeated references the lists can contain many
    # duplicates. The final endpoint(s) for a pseudo-path must expose the
    # unique set (as params_to_hash and the optimizer's merge logic do).
    # We dedup here in first-seen order so that we construct far fewer
    # Endpoint objects while still producing identical observable param
    # sets for every (method, url) pair.
    private def unique_params_preserve_order(params : Array(Param)) : Array(Param)
      seen = Set(Tuple(String, String)).new
      result = [] of Param
      params.each do |p|
        key = {p.name, p.param_type}
        unless seen.includes?(key)
          seen.add(key)
          result << p
        end
      end
      result
    end

    private def attach_file_callees(endpoints : Array(Endpoint), content : String, path : String)
      callees = Noir::PhpCalleeExtractor.callees_for_body(executable_file_content(content), path, 1)
      endpoints.each do |endpoint|
        attach_php_callees(endpoint, callees)
      end
    end

    private def executable_file_content(content : String) : String
      declaration_ranges = [] of Tuple(Int32, Int32)
      declaration_regex = /\b(?:abstract\s+|final\s+)?(?:class|interface|trait|enum)\s+[A-Za-z_]\w*[^{]*\{|\bfunction\s+&?\s*[A-Za-z_]\w*[^{]*\{/m
      offset = 0

      while offset < content.size
        match = declaration_regex.match(content, offset)
        break unless match

        brace_pos = match.end(0) - 1
        close_pos = find_matching_php_close_brace(content, brace_pos)
        unless close_pos
          offset = match.end(0)
          next
        end

        declaration_ranges << {match.begin(0), close_pos + 1}
        offset = close_pos + 1
      end

      return content if declaration_ranges.empty?

      blank_ranges(content, declaration_ranges)
    end

    private def blank_ranges(content : String, ranges : Array(Tuple(Int32, Int32))) : String
      String.build do |io|
        offset = 0
        ranges.each do |range_start, range_end|
          io << content[offset...range_start]
          io << blank_preserving_newlines(content[range_start...range_end])
          offset = range_end
        end
        io << content[offset..]
      end
    end

    private def blank_preserving_newlines(content : String) : String
      String.build do |io|
        content.each_char do |char|
          io << (char == '\n' ? '\n' : ' ')
        end
      end
    end

    def allow_patterns
      ["$_GET", "$_POST", "$_REQUEST", "$_SERVER", "$_COOKIE", "$_FILES", "filter_input"]
    end
  end
end
