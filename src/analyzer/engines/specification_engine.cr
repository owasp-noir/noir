require "../../models/analyzer"
require "../../models/code_locator"
require "uri"
require "../../models/locator_keys"

module Analyzer::Specification
  # Base for the specification-format analyzers (OpenAPI, Postman, HAR,
  # Terraform, k8s manifests, proxy exports, …).
  #
  # They do not walk the file tree the way the language engines do. The
  # detector recognises a document and pushes its path into `CodeLocator`
  # under a key, and the analyzer later drains that key. Forty-odd
  # analyzers each open-coded the same drain:
  #
  #     locator = CodeLocator.instance
  #     files = locator.all(Noir::LocatorKeys::OAS3_JSON)
  #     return @result unless files.is_a?(Array(String))
  #     files.each do |path|
  #       next unless File.exists?(path)
  #       begin
  #         ...
  #       rescue e
  #         @logger.debug "..."
  #         @logger.debug_sub e
  #       end
  #     end
  #
  # with just enough variation between copies that some dropped the
  # existence check, some dropped the per-file rescue (letting one
  # malformed document abort every remaining file for that analyzer), and
  # the log wording differed everywhere. `each_spec_file` is that drain,
  # once.
  abstract class SpecificationEngine < Analyzer
    # Yield every registered path for `key`, skipping paths that no longer
    # resolve and containing per-file failures.
    #
    # The `File.exists?` check is load-bearing, not a leftover. Unlike the
    # language engines — whose paths come from the extension index rebuilt
    # per scan — these keys are never cleared at the start of a scan
    # (`detect_techs` clears only `file_map` and the mobile keys, and
    # `clear_all` runs only between the two halves of a `--diff` run). A
    # second scan in the same process therefore still sees the first
    # scan's registrations, and dropping the check would turn stale
    # entries into read errors.
    #
    # Failures are contained per file: a malformed document is logged and
    # skipped so the remaining files for that analyzer still produce
    # endpoints.
    #
    # `sorted` yields in lexical path order. Only pass it where order is part
    # of the format's meaning — Supabase migrations are named
    # `<timestamp>_<name>.sql`, so lexical order is chronological and a column
    # added in one file and dropped in another only comes out right if they
    # are applied in sequence. Registration order is otherwise whatever the
    # concurrent detector walk produced, so relying on it silently would be a
    # bug.
    protected def each_spec_file(key : Noir::LocatorKey(Array(String)), sorted : Bool = false, &block : String -> Nil) : Nil
      # No `is_a?(Array(String))` guard: `CodeLocator#all` is typed to return
      # `Array(String)`, so the copies of that check in the old analyzers were
      # always true and only read as though `all` might hand back something
      # else.
      paths = CodeLocator.instance.all(key)
      paths = paths.sort if sorted

      paths.each do |path|
        next unless File.exists?(path)

        begin
          block.call(path)
        rescue e
          logger.debug "#{self.class} failed to process #{path}"
          logger.debug_sub e
        end
      end
    end

    # `each_spec_file` plus the `Details` almost every caller builds from
    # the path as its first statement.
    protected def each_spec_file_with_details(key : Noir::LocatorKey(Array(String)), &block : String, Details -> Nil) : Nil
      each_spec_file(key) do |path|
        block.call(path, Details.new(PathInfo.new(path)))
      end
    end

    # `scheme://` prefix of an absolute URL. `//host/path` is deliberately not
    # matched here — it is protocol-relative and handled separately.
    ABSOLUTE_SERVER_URL = /\A[A-Za-z][A-Za-z0-9+.\-]*:\/\//

    # Turns an OpenAPI-style `servers[].url` list into the base path every
    # endpoint in the document hangs off. Shared by OAS3 and OpenRPC, which
    # use the same `servers` object.
    #
    # The first entry that yields a usable path wins, mirroring how OAS2's
    # single `basePath` and RAML's single `baseUri` behave.
    protected def server_base_path(server_urls : Array(String)) : String
      server_urls.each do |server_url|
        path = server_url_path(server_url)
        next if path.nil?
        return combine_base_url(path)
      rescue
        next
      end

      @url
    end

    # The path a single `servers[].url` contributes, or nil when the entry
    # contributes nothing (unusable, or a host the user did not ask about).
    protected def server_url_path(server_url : String) : String?
      return if server_url.empty?

      # Absolute (`https://host/v1`) and protocol-relative (`//host/v1`) URLs
      # both carry an authority; only the path part belongs in the endpoint
      # URL. Treating the whole thing as a path is what produced base paths
      # like `/api.openapi-generator.tech`.
      absolute = server_url.matches?(ABSOLUTE_SERVER_URL)
      if absolute || server_url.starts_with?("//")
        uri = URI.parse(absolute ? server_url : "http:#{server_url}")
        # With `--url` supplied, a multi-host document should only contribute
        # the server the user actually pointed at.
        unless @url.empty?
          return unless URI.parse(@url).host == uri.host
        end
        return uri.path
      end

      return server_url if server_url.starts_with?('/')

      # An unrooted relative reference such as `api/v1` is a legal server URL,
      # but a bare host (`api.example.com/v1`) or an unresolved placeholder
      # (`<local-terminal-IP-address>`) is not a path — rooting either invents
      # a leading segment no request ever carries.
      return unless relative_server_path?(server_url)
      "/#{server_url}"
    end

    # True when an unrooted `servers[].url` reads as a path rather than as a
    # host or a placeholder. `.` and `:` in the first segment mean a hostname
    # or a `host:port`; anything outside the unreserved URL characters (plus
    # the `{}` of a server variable) means the document left a placeholder in.
    private def relative_server_path?(server_url : String) : Bool
      first = server_url.split('/', 2).first
      return false if first.empty?
      return false if first.includes?('.') || first.includes?(':')
      first.each_char.all? do |char|
        char.ascii_alphanumeric? || "-_~%{}".includes?(char)
      end
    end

    # Joins the user-supplied `--url` with a document-declared base path
    # without doubling or dropping the separator.
    protected def combine_base_url(path : String) : String
      return @url if path.empty?
      return path if @url.empty?
      if @url.ends_with?("/") && path.starts_with?("/")
        @url + path[1..]
      elsif !@url.ends_with?("/") && !path.starts_with?("/")
        "#{@url}/#{path}"
      else
        @url + path
      end
    end
  end
end
