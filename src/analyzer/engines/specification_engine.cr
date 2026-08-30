require "../../models/analyzer"
require "../../models/code_locator"
require "../../models/skipped_files"
require "uri"
require "json"
require "yaml"
require "../../models/locator_keys"
require "../../utils/media_filter"
require "../../utils/yaml"

module Analyzer::Specification
  # A parsed specification document together with the path it was read from.
  #
  # A `$ref` is relative to the file that writes it, not to the document the
  # scan started from: once an operation has been pulled in from
  # `paths/activity/activities.yaml`, its
  # `../../openapi.yaml#/components/parameters/Fields` has to resolve from
  # *that* file's directory. A node carried across a file boundary therefore
  # has to carry its origin with it, which is precisely what passing the entry
  # root alone — all the analyzers needed while every ref was same-document —
  # cannot express.
  struct SpecDoc(T)
    getter root : T
    getter path : String

    def initialize(@root : T, @path : String)
    end
  end

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
    # `scheme://host/…` and protocol-relative `//host/…` ref targets.
    REMOTE_REF = /\A(?:[A-Za-z][A-Za-z0-9+.\-]*:)?\/\//

    # Documents pulled in by a file `$ref`, keyed by expanded path. Directus's
    # 70 split path files hold 640 refs back into the entry document; without
    # this it would be parsed 640 times.
    #
    # A nil entry is a negative cache: a target that was missing, out of scope
    # or unparsable stays that way for the rest of the run, so a broken ref
    # costs one failed read rather than one per occurrence.
    @external_json_docs = {} of String => SpecDoc(JSON::Any)?
    @external_yaml_docs = {} of String => SpecDoc(YAML::Any)?
    @reported_refs = Set(String).new

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
          # This walk is the one behind all 45 spec analyzers and it was the
          # only per-file rescue in the codebase that never told anyone: a
          # malformed OpenAPI document, a truncated HAR, a Postman export
          # with a bad `$ref` produced zero endpoints, no warning, and
          # `"errors": []`.
          Noir::SkippedFiles.record(tech, path, e.message.presence || e.class.name)
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

    # Same-document `$ref` resolution, for the analyzers that have only a
    # document root to resolve against.
    #
    # A ref that names a file is not resolved here: the caller has to say
    # *which* file wrote the ref before a relative path means anything, and
    # that is the `SpecDoc` overload below.
    protected def resolve_ref_json(root : JSON::Any, ref : String) : JSON::Any?
      return unless ref.starts_with?("#/")
      resolve_pointer_json(root, ref[1..])
    end

    # `resolve_ref_json` for the YAML parse of the same formats. Kept
    # separate rather than generic because the two `Any` types are
    # unrelated and their hashes are keyed differently — YAML mappings are
    # keyed by `YAML::Any`, not by `String`.
    protected def resolve_ref_yaml(root : YAML::Any, ref : String) : YAML::Any?
      return unless ref.starts_with?("#/")
      resolve_pointer_yaml(root, ref[1..])
    end

    # Walks a JSON Pointer (RFC 6901) from a document root — OAS2's
    # `/definitions/Name`, OAS3's `/components/schemas/Name`, AsyncAPI's
    # `/components/messages/Name`.
    #
    # `~1` and `~0` are unescaped in that order — `~0` must be decoded last
    # or a literal `~1` in a key would be corrupted by the `~` produced from
    # `~0`.
    #
    # An empty pointer is the whole document, which is what a bare
    # `./paths/pets.yaml` ref resolves to. Returns nil at the first segment
    # that is not a mapping or is absent, which is what lets callers treat a
    # dangling ref as "no schema" instead of raising mid-walk.
    protected def resolve_pointer_json(root : JSON::Any, pointer : String) : JSON::Any?
      return root if pointer.empty?
      return unless pointer.starts_with?('/')
      node = root
      pointer[1..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[decoded]?
        node = next_node
      end
      node
    end

    protected def resolve_pointer_yaml(root : YAML::Any, pointer : String) : YAML::Any?
      return root if pointer.empty?
      return unless pointer.starts_with?('/')
      node = root
      pointer[1..].split('/').each do |segment|
        decoded = segment.gsub("~1", "/").gsub("~0", "~")
        return unless hash = node.as_h?
        return unless next_node = hash[YAML::Any.new(decoded)]?
        node = next_node
      end
      node
    end

    # Follows a `$ref` written in `doc`, across a local file boundary when it
    # names one. Three forms occur and all three land here:
    #
    #     $ref: '#/components/schemas/Pet'                   same document
    #     $ref: './paths/activity/activities.yaml'           another file, whole
    #     $ref: '../../openapi.yaml#/components/parameters/Fields'
    #
    # Splitting a large specification across files is the maintained shape
    # every OpenAPI toolchain recommends, and the third form is how the parts
    # reach back into the shared components — Directus's 70 path files write
    # it 640 times between them. Declining the fragment would read the
    # operations but lose every parameter they declare.
    #
    # Returns the node *together with the document it lives in*, because a
    # ref nested inside that node resolves against the file it was read from,
    # not against the caller's.
    protected def resolve_ref_json(doc : SpecDoc(JSON::Any), ref : String) : Tuple(JSON::Any, SpecDoc(JSON::Any))?
      file, pointer = split_ref(ref)

      if file.empty?
        node = resolve_pointer_json(doc.root, pointer)
        return node.nil? ? nil : {node, doc}
      end

      return unless target = external_json_doc(doc.path, file)
      node = resolve_pointer_json(target.root, pointer)
      node.nil? ? nil : {node, target}
    end

    protected def resolve_ref_yaml(doc : SpecDoc(YAML::Any), ref : String) : Tuple(YAML::Any, SpecDoc(YAML::Any))?
      file, pointer = split_ref(ref)

      if file.empty?
        node = resolve_pointer_yaml(doc.root, pointer)
        return node.nil? ? nil : {node, doc}
      end

      return unless target = external_yaml_doc(doc.path, file)
      node = resolve_pointer_yaml(target.root, pointer)
      node.nil? ? nil : {node, target}
    end

    # Splits a `$ref` into its file part and its JSON Pointer; either may be
    # empty.
    protected def split_ref(ref : String) : Tuple(String, String)
      if index = ref.index('#')
        {ref[0, index], ref[(index + 1)..]}
      else
        {ref, ""}
      end
    end

    # Cycle-breaking identity for a ref. The ref string on its own stopped
    # being one the moment refs could cross files: `./common.yaml` names a
    # different file in every directory, and `#/components/schemas/Pet` a
    # different node in every document. Two files that ref each other
    # therefore terminate on the second visit rather than recursing until the
    # stack runs out.
    protected def ref_key(doc : SpecDoc, ref : String) : String
      "#{doc.path}\u0000#{ref}"
    end

    private def external_json_doc(from_path : String, file_ref : String) : SpecDoc(JSON::Any)?
      return unless path = external_ref_path(from_path, file_ref)
      return @external_json_docs[path] if @external_json_docs.has_key?(path)

      # A JSON document's refs are parsed as JSON, even when they name a
      # `.yaml` file: grafting a `YAML::Any` subtree onto a `JSON::Any`
      # document is not something the two unrelated `Any` types allow, so a
      # cross-format target is reported unresolved rather than silently
      # dropped. The YAML side needs no such rule — YAML is a superset of
      # JSON, so a YAML document may ref a `.json` file and get it parsed.
      @external_json_docs[path] = begin
        if content = read_ref_file(from_path, path, file_ref)
          SpecDoc.new(JSON.parse(content), path)
        end
      rescue e
        record_ref_gap(from_path, file_ref, e.message.presence || e.class.name)
      end
    end

    private def external_yaml_doc(from_path : String, file_ref : String) : SpecDoc(YAML::Any)?
      return unless path = external_ref_path(from_path, file_ref)
      return @external_yaml_docs[path] if @external_yaml_docs.has_key?(path)

      @external_yaml_docs[path] = begin
        if content = read_ref_file(from_path, path, file_ref)
          SpecDoc.new(parse_yaml(content), path)
        end
      rescue e
        record_ref_gap(from_path, file_ref, e.message.presence || e.class.name)
      end
    end

    # The local file a `$ref` names, or nil when it names one this scan will
    # not read.
    private def external_ref_path(from_path : String, file_ref : String) : String?
      if file_ref.matches?(REMOTE_REF)
        # noir makes no network requests during a scan. A document that hangs
        # its operations off an `https://` ref is reported as unread rather
        # than fetched behind the user's back.
        return record_ref_gap(from_path, file_ref, "remote target is not fetched")
      end

      target = File.expand_path(file_ref, File.dirname(File.expand_path(from_path)))

      # Containment rule: a ref target must resolve inside one of the scan
      # bases the user passed, and must not be a path they excluded. A
      # specification document is untrusted input — `../../../../etc/passwd`
      # is a well-formed ref — and a scan has no business reading, still less
      # reporting, a file outside the tree it was pointed at. The comparison
      # runs on expanded paths, so no arrangement of `..` segments or
      # trailing separators walks around it.
      #
      # `..` *within* the tree stays legal, and has to: every one of
      # Directus's path files reaches back to `../../openapi.yaml`, so a
      # blanket "no parent segments" rule would decline the very layout this
      # exists to read.
      #
      # Expansion is textual, which leaves one way out of the tree that this
      # check cannot see: a link inside it. `read_ref_file` closes that by
      # refusing to follow symlinks at all, as the detector walk does.
      unless within_scan_base?(target)
        return record_ref_gap(from_path, file_ref, "target is outside the scan base")
      end

      if excluded_path?(target)
        return record_ref_gap(from_path, file_ref, "target is excluded by --exclude-path")
      end

      target
    end

    # Reads a ref target, or records why it could not be read.
    private def read_ref_file(from_path : String, target : String, file_ref : String) : String?
      # `follow_symlinks: false`, the same stat the detector walk makes: it
      # skips symlinked and non-regular entries outright, so following one
      # here would diverge from the rest of the scan *and* hand a document a
      # way around containment, since a link inside the tree can point
      # anywhere. A FIFO is the sharper case — reading one never returns.
      info = File.info?(target, follow_symlinks: false)
      return record_ref_gap(from_path, file_ref, "target not found") unless info
      unless info.file?
        reason = info.type.symlink? ? "target is a symbolic link (not followed)" : "target is not a regular file (#{info.type})"
        return record_ref_gap(from_path, file_ref, reason)
      end

      # The size and binary budget the detector walk applies to a document it
      # finds itself. A ref is a second way into the file tree, not a way
      # around that budget.
      if reason = MediaFilter.skip_check(target, info: info)
        return record_ref_gap(from_path, file_ref, reason)
      end

      read_file_content(target)
    end

    # Reports a ref that was declined or could not be read, once per distinct
    # ref. A split document repeats the same ref in operation after operation,
    # so recording per occurrence would tally one broken target hundreds of
    # times.
    #
    # What gets recorded is the referring document, not the resolved target:
    # the document is a path inside the scan, reported the way the scan
    # reports every other path, while the resolved target is expanded and
    # would put the scanning machine's directory layout into a report that may
    # be shared. The ref goes into the message exactly as the document wrote
    # it, which is also the string a reader has to go and fix.
    #
    # It lands in `errors` — and in `--strict`'s exit code — like every other
    # coverage gap, because the operations behind an unread ref are endpoints
    # the scan did not find, and a silently shorter list is exactly what
    # `SkippedFiles` exists to prevent.
    private def record_ref_gap(from_path : String, file_ref : String, reason : String) : Nil
      message = "unresolved $ref '#{file_ref}': #{reason}"
      return unless @reported_refs.add?("#{from_path}\u0000#{message}")
      logger.debug "#{from_path}: #{message}"
      Noir::SkippedFiles.record(tech, from_path, message, noun: "referenced file")
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
