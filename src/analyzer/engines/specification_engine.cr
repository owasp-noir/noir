require "../../models/analyzer"
require "../../models/code_locator"
require "uri"
require "json"
require "yaml"
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
    # The `File.exists?` check is load-bearing, not a leftover — but not for
    # the reason it used to be. It once compensated for these keys never
    # being cleared: a second scan in the same process saw the first scan's
    # registrations, and this guard was all that stopped them being read.
    # `LocatorKeys.reset` now drops them at the top of every detect pass, so
    # that is no longer what it is for.
    #
    # What remains: the detect→analyze window is real wall-clock time on a
    # large tree, and a file can be deleted or a build directory swept
    # inside it. Library callers driving `analysis_endpoints` directly, with
    # their own `Process`-lifetime keys, get no automatic reset by design.
    # And it is the containment boundary that keeps one vanished file from
    # becoming a logged read error in each of the 45 spec analyzers.
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

    # Follows a local JSON Pointer — OAS2's `#/definitions/Name`, OAS3's
    # `#/components/schemas/Name`, AsyncAPI's `#/components/messages/Name`
    # — against the document root.
    #
    # Only same-document refs are resolved: a ref that does not start with
    # `#/` points at another file (or an external URL) that the analyzer
    # never loaded, so it returns nil rather than guessing.
    #
    # `~1` and `~0` are unescaped per RFC 6901, in that order — `~0` must be
    # decoded last or a literal `~1` in a key would be corrupted by the `~`
    # produced from `~0`.
    #
    # Returns nil at the first segment that is not a mapping or is absent,
    # which is what lets callers treat a dangling ref as "no schema" instead
    # of raising mid-walk.
    protected def resolve_ref_json(root : JSON::Any, ref : String) : JSON::Any?
      return unless ref.starts_with?("#/")
      node = root
      ref[2..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[decoded]?
        node = next_node
      end
      node
    end

    # `resolve_ref_json` for the YAML parse of the same formats. Kept
    # separate rather than generic because the two `Any` types are
    # unrelated and their hashes are keyed differently — YAML mappings are
    # keyed by `YAML::Any`, not by `String`.
    protected def resolve_ref_yaml(root : YAML::Any, ref : String) : YAML::Any?
      return unless ref.starts_with?("#/")
      node = root
      ref[2..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[YAML::Any.new(decoded)]?
        node = next_node
      end
      node
    end

    # Appends a valueless `Param` unless an equal one is already present.
    #
    # Schema walks reach the same property twice whenever a document
    # composes schemas (`allOf`, a `$ref` pulled in from two places), so the
    # dedupe is load-bearing, not defensive. Equality is full `Param`
    # equality; the value is always `""` here, so it reduces to name +
    # param_type.
    protected def add_param(params : Array(Param), name : String, param_type : String)
      return if name.empty?
      param = Param.new(name, "", param_type)
      params << param unless params.includes?(param)
    end
  end
end
