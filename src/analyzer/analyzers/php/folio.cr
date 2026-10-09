require "../../engines/php_engine"

module Analyzer::Php
  # Laravel Folio maps Blade views under a mounted directory to GET routes:
  #
  #     Folio::path(resource_path('views/pages'))->uri('/')->middleware([
  #         'admin/*' => ['auth'],
  #     ]);
  #
  #     pages/users/index.blade.php   → GET /users
  #     pages/users/[User].blade.php  → GET /users/{user}
  #     pages/docs/[...slug].blade.php → GET /docs/{slug}
  #
  # Mounts come from `Folio::path(...)` chains in service providers; with
  # none found the installer default (`resources/views/pages` at `/`) is
  # used. Middleware from the mount's pattern map and from the page's own
  # `middleware([...])` call is reported as a tag.
  class Folio < PhpEngine
    analyzer_for "php_folio"

    TAGGER = "folio_analyzer"

    record Mount, dir : String, uri : String, middleware : Array(Tuple(Regex, Array(String)))

    DEFAULT_MOUNT        = Mount.new("resources/views/pages", "/", [] of Tuple(Regex, Array(String)))
    PATH_CALL_RE         = /\bFolio::path\s*\(\s*(resource_path|base_path|app_path)\s*\(\s*['"]([^'"]*)['"]\s*\)/
    URI_RE               = /->\s*uri\s*\(\s*['"]([^'"]*)['"]/
    MOUNT_MIDDLEWARE_RE  = /->\s*middleware\s*\(\s*\[/
    PATTERN_ENTRY_RE     = /['"]([^'"]+)['"]\s*=>\s*\[([^\]]*)\]/
    PAGE_MIDDLEWARE_RE   = /(?<![\w>:$\\])middleware\s*\(\s*(\[[^\]]*\]|'[^']*'|"[^"]*")/
    STRING_RE            = /'([^']*)'|"([^"]*)"/
    DYNAMIC_SEGMENT_RE   = /\A\[(?:\.\.\.)?([^\]:]+)(?::[^\]]*)?\]\z/
    PATH_HELPER_PREFIXES = {"resource_path" => "resources", "base_path" => "", "app_path" => "app"}

    @mounts = [] of Mount

    def analyze
      found = ordered_file_scan do |path|
        next if path.ends_with?(".blade.php")
        content = read_file_content(path)
        mounts_in(path, content) if content.includes?("Folio::path")
      end.flatten
      @mounts = found.empty? ? [DEFAULT_MOUNT] : found.sort_by { |mount| -mount.dir.size }
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless path.ends_with?(".blade.php")

      rel = "/" + base_relative_path(path)
      @mounts.each do |mount|
        idx = rel.index("/#{mount.dir}/")
        next unless idx

        page = rel[(idx + mount.dir.size + 2)..].rchop(".blade.php")
        url = page_url(mount.uri, page)
        middleware = mount_middleware(mount, url.lchop('/'))
        middleware.concat(page_middleware(read_file_content(path)))
        middleware.uniq!

        endpoint = Endpoint.new(url, "GET", extract_brace_path_params(url), Details.new(PathInfo.new(path, 1)))
        unless middleware.empty?
          endpoint.add_tag(Tag.new("middleware", middleware.join(", "), TAGGER))
          if guard = middleware.find(&.starts_with?("auth"))
            endpoint.add_tag(Tag.new("auth", "Protected by Folio middleware #{guard}", TAGGER))
          end
        end
        endpoints << endpoint
        break
      end
      endpoints
    rescue e
      logger.debug "Error analyzing Folio page #{path}: #{e}"
      Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
      [] of Endpoint
    end

    private def mounts_in(path : String, content : String) : Array(Mount)
      code = php_code(content)
      lexer = Noir::PhpLexer.new(code)
      mounts = [] of Mount
      code.scan(PATH_CALL_RE) do |m|
        next unless lexer.in_code?(m.begin(0))
        chain = code[m.begin(0)...lexer.statement_end(m.begin(0))]
        dir = File.join(PATH_HELPER_PREFIXES[m[1]], m[2]).strip('/')
        uri = chain.match(URI_RE).try(&.[1]) || "/"
        patterns = [] of Tuple(Regex, Array(String))
        if mw = chain.match(MOUNT_MIDDLEWARE_RE)
          chain[mw.end(0)..].scan(PATTERN_ENTRY_RE) do |entry|
            pattern = Regex.new("\\A#{Regex.escape(entry[1].strip('/')).gsub("\\*", ".*")}\\z")
            patterns << {pattern, strings(entry[2])}
          end
        end
        mounts << Mount.new(dir, uri, patterns)
      end
      mounts
    end

    private def mount_middleware(mount : Mount, uri : String) : Array(String)
      mount.middleware.select { |(pattern, _)| uri.matches?(pattern) }.flat_map(&.[1])
    end

    # `middleware(['auth', 'verified'])` inside the page's PHP block.
    private def page_middleware(content : String) : Array(String)
      return [] of String unless content.includes?("middleware")
      lexer = Noir::PhpLexer.new(content)
      found = [] of String
      content.scan(PAGE_MIDDLEWARE_RE) do |m|
        found.concat(strings(m[1])) if lexer.in_code?(m.begin(0))
      end
      found
    end

    private def strings(text : String) : Array(String)
      text.scan(STRING_RE).map { |m| m[1]? || m[2] }
    end

    # `users/[User]` → `/users/{user}`; a trailing `index` is the directory.
    private def page_url(mount_uri : String, page : String) : String
      segments = page.split('/')
      segments.pop if segments.last == "index"
      segments = segments.map do |segment|
        if m = segment.match(DYNAMIC_SEGMENT_RE)
          # `[.App.Models.User]` / `[User:slug]` bind `$user`.
          name = m[1].split(/[.\\]/).reject(&.empty?).last? || m[1]
          "{#{name[0].downcase}#{name[1..]}}"
        else
          segment
        end
      end
      "/" + ([mount_uri.strip('/')] + segments).reject(&.empty?).join('/')
    end
  end
end
