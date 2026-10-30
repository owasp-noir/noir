require "../../engines/specification_engine"

module Analyzer::Specification
  class K8sIngress < SpecificationEngine
    analyzer_for "k8s_ingress"

    # A rule routes every method to its backend.
    METHOD_ANY             = "ANY"
    REWRITE_ANNOTATION     = "nginx.ingress.kubernetes.io/rewrite-target"
    AUTH_ANNOTATION_PREFIX = "nginx.ingress.kubernetes.io/"
    DEFAULT_PATH_TYPE      = "ImplementationSpecific"
    API_VERSION_LINE       = /(?m)^[ \t-]*apiVersion:\s*["']?(?:networking\.k8s\.io\/[^"'\s#]+|extensions\/v1beta1)["']?\s*(?:#.*)?$/
    KIND_LINE              = /(?m)^[ \t-]*kind:\s*["']?Ingress["']?\s*(?:#.*)?$/
    PATH_LINE              = /^[ \t-]*path:\s*(.*)$/
    PATH_TYPE_LINE         = /^[ \t-]*pathType:\s*(.*)$/
    HOST_LINE              = /^[ \t-]*host:\s*(.*)$/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::K8S_INGRESS_SPEC) do |path, details|
        content = read_file_content(path)
        begin
          path_lines = path_lines(content)
          YAML.parse_all(content).each { |doc| process_doc(doc, details, path_lines) }
        rescue e
          # Kept as an explicit rescue rather than delegating to the engine:
          # a Helm chart's `templates/ingress.yaml` is a Go template, so
          # `path: {{ .Values.server.ingress.path }}` is not valid YAML and
          # the parse legitimately fails. That is the common case, not an
          # error — fall back to the tolerant line scanner instead of
          # letting the file be logged and skipped.
          @logger.debug "Exception processing #{path}, falling back to tolerant Ingress template extraction"
          @logger.debug_sub e
          process_template(content, details)
        end
      end

      @result
    end

    private def process_doc(doc : YAML::Any, details : Details, path_lines : Hash(String, Int32))
      root = doc.as_h?
      return unless root

      kind = root[YAML::Any.new("kind")]?.try(&.as_s?)
      if kind == "List"
        items = root[YAML::Any.new("items")]?.try(&.as_a?) || [] of YAML::Any
        items.each { |item| process_doc(item, details, path_lines) }
        return
      end

      return unless kind == "Ingress"

      api_version = root[YAML::Any.new("apiVersion")]?.try(&.as_s?)
      return unless supported_api_version?(api_version)

      metadata = root[YAML::Any.new("metadata")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      annotations = metadata[YAML::Any.new("annotations")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      rewrite_target = annotations[YAML::Any.new(REWRITE_ANNOTATION)]?.try(&.as_s?)
      access = access_tag(annotations)

      spec = root[YAML::Any.new("spec")]?.try(&.as_h?)
      return unless spec

      tls_hosts = collect_tls_hosts(spec[YAML::Any.new("tls")]?)
      process_default_backend(spec[YAML::Any.new("defaultBackend")]?, tls_hosts, details, access)

      rules = spec[YAML::Any.new("rules")]?.try(&.as_a?) || [] of YAML::Any
      rules.each { |rule| process_rule(rule, tls_hosts, rewrite_target, details, path_lines, access) }
    end

    # ingress-nginx enforces these on every location the Ingress generates:
    # `auth-url` is an nginx `auth_request` subrequest, `auth-type` with its
    # `auth-secret` is `auth_basic`/digest, and `auth-tls-secret` verifies
    # client certificates unless `auth-tls-verify-client` relaxes it
    # (`optional`, `optional_no_ca` and `off` admit callers without one).
    # ponytail: the default `nginx.ingress.kubernetes.io` prefix only; a
    # controller run with `--annotations-prefix` is not recognised.
    #
    # A value with a Helm action in it (`{{ .Values.authUrl }}`, `{{ if }}`)
    # is whatever the chart's values make it, possibly empty, so a guard that
    # rests only on such values is one a setting can lift.
    private def access_tag(annotations : Hash(YAML::Any, YAML::Any)) : Tag?
      value = ->(name : String) { annotations[YAML::Any.new(AUTH_ANNOTATION_PREFIX + name)]?.try(&.as_s?).try(&.strip).presence }
      templated = ->(values : Array(String)) { values.any?(&.includes?("{{")) }
      guards = [] of Tuple(String, Bool)
      if url = value.call("auth-url")
        guards << {"auth-url #{url}", templated.call([url])}
      end
      if (type = value.call("auth-type")) && (secret = value.call("auth-secret"))
        guards << {"auth-type #{type}", templated.call([type, secret])}
      end
      tls_secret = value.call("auth-tls-secret")
      verify = value.call("auth-tls-verify-client") || "on"
      if tls_secret && (verify.downcase == "on" || templated.call([verify]))
        guards << {"auth-tls-verify-client on", templated.call([tls_secret, verify])}
      end
      return if guards.empty?

      note = " (a setting can make it public)" if guards.all?(&.[1])
      declared_access_tag("Protected by ingress-nginx #{guards.join(", ", &.[0])}#{note}")
    end

    private def supported_api_version?(api_version : String?) : Bool
      return false unless api_version

      api_version.starts_with?("networking.k8s.io/") || api_version == "extensions/v1beta1"
    end

    private def collect_tls_hosts(node : YAML::Any?) : Set(String)
      hosts_set = Set(String).new
      return hosts_set if node.nil?
      arr = node.as_a?
      return hosts_set unless arr
      arr.each do |entry|
        h = entry.as_h?
        next unless h
        hosts = h[YAML::Any.new("hosts")]?.try(&.as_a?) || [] of YAML::Any
        hosts.each do |host|
          if str = host.as_s?
            hosts_set << str unless str.empty?
          end
        end
      end
      hosts_set
    end

    private def process_rule(rule : YAML::Any, tls_hosts : Set(String), rewrite_target : String?, details : Details, path_lines : Hash(String, Int32), access : Tag?)
      rule_h = rule.as_h?
      return unless rule_h

      host = rule_h[YAML::Any.new("host")]?.try(&.as_s?) || ""
      http = rule_h[YAML::Any.new("http")]?.try(&.as_h?)
      return unless http

      paths = http[YAML::Any.new("paths")]?.try(&.as_a?) || [] of YAML::Any
      paths.each do |path_entry|
        path_h = path_entry.as_h?
        next unless path_h

        path = path_h[YAML::Any.new("path")]?.try(&.as_s?) || ""
        path = "/" if path.empty? && backend_present?(path_h[YAML::Any.new("backend")]?)
        next if path.empty?

        path_type = path_h[YAML::Any.new("pathType")]?.try(&.as_s?) || DEFAULT_PATH_TYPE
        rule_details = line_details(details, path_lines[path]?)
        emit_endpoint(path, path_type, host, tls_hosts, rule_details, access: access)

        if rewrite_target && !rewrite_target.empty?
          rewritten = strip_capture_groups(rewrite_target)
          if rewritten != path
            emit_endpoint(rewritten, path_type, host, tls_hosts, rule_details, "rewrite", access)
          end
        end
      end
    end

    private def process_default_backend(default_backend : YAML::Any?, tls_hosts : Set(String), details : Details, access : Tag?)
      return unless backend_present?(default_backend)

      emit_endpoint("/", DEFAULT_PATH_TYPE, "", tls_hosts, details, "default-backend", access)
    end

    private def backend_present?(backend : YAML::Any?) : Bool
      backend.try(&.as_h?) != nil
    end

    private def emit_endpoint(path : String, path_type : String, host : String, tls_hosts : Set(String), details : Details, origin : String = "rule", access : Tag? = nil)
      # ingress-nginx reads `ImplementationSpecific` paths as regexes when
      # `use-regex` is on; `Exact` / `Prefix` paths are literal.
      # GCE / ALB spell a prefix as `/static/*` under the same path type.
      regex = path_type == "ImplementationSpecific" && Noir::URLPath.regex_route?(path.ends_with?("/*") ? path.rchop('*') : path)
      path = Noir::URLPath.strip_regex_anchors(path) if path_type == "ImplementationSpecific"
      endpoint = Endpoint.new(path, METHOD_ANY, details)
      endpoint.kind = "regex" if regex
      endpoint.add_tag(Tag.new("ingress-path-type", path_type.downcase, "k8s_ingress_analyzer"))
      endpoint.add_tag(Tag.new("ingress-host", host, "k8s_ingress_analyzer")) unless host.empty?
      endpoint.add_tag(Tag.new("ingress-source", origin, "k8s_ingress_analyzer"))
      endpoint.add_tag(access) if access
      endpoint.protocol = "https" if !host.empty? && tls_hosts.includes?(host)
      @result << endpoint
    end

    # `rewrite-target` values commonly reference capture groups (e.g. `/$2`).
    # Surface them as bare path segments since downstream consumers expect
    # plain URL strings, not regex back-references.
    private def strip_capture_groups(target : String) : String
      target.gsub(/\$\d+/, "")
    end

    private def process_template(content : String, details : Details)
      return unless content.matches?(API_VERSION_LINE) && content.matches?(KIND_LINE)

      tls_hosts = Set(String).new
      rewrite_target = extract_rewrite_target(content)
      lines = content.lines
      host = ""
      emitted = Set(String).new

      lines.each_with_index do |line, index|
        if host_match = line.match(HOST_LINE)
          host = clean_template_host(host_match[1])
          next
        end

        path_match = line.match(PATH_LINE)
        next unless path_match

        path = clean_template_path(path_match[1]) || "/"
        path_type = find_template_path_type(lines, index) || DEFAULT_PATH_TYPE
        rule_details = line_details(details, index + 1)
        emit_template_endpoint(path, path_type, host, tls_hosts, rule_details, emitted)

        if rewrite_target && !rewrite_target.empty?
          rewritten = strip_capture_groups(rewrite_target)
          emit_template_endpoint(rewritten, path_type, host, tls_hosts, rule_details, emitted, "rewrite") unless rewritten == path
        end
      end

      if emitted.empty? && content.matches?(/(?m)^[ \t]*defaultBackend:\s*(?:#.*)?$/)
        emit_template_endpoint("/", DEFAULT_PATH_TYPE, "", tls_hosts, details, emitted, "default-backend")
      end
    end

    private def emit_template_endpoint(path : String, path_type : String, host : String, tls_hosts : Set(String), details : Details, emitted : Set(String), origin : String = "template")
      key = "#{origin}\0#{host}\0#{path_type}\0#{path}"
      return if emitted.includes?(key)

      emitted << key
      emit_endpoint(path, path_type, host, tls_hosts, details, origin)
    end

    # Line of each `path:` value. `YAML::Any` keeps no positions, so the
    # parsed rule is matched back to the text by value.
    # ponytail: a path repeated across rules gets its first line.
    private def path_lines(content : String) : Hash(String, Int32)
      lines = {} of String => Int32
      content.each_line.with_index(1) do |line, number|
        next unless (match = line.match(PATH_LINE)) && (path = clean_template_path(match[1]))
        lines[path] ||= number
      end
      lines
    end

    private def line_details(details : Details, line : Int32?) : Details
      return details unless line && (path_info = details.code_paths.first?)
      Details.new(PathInfo.new(path_info.path, line))
    end

    private def extract_rewrite_target(content : String) : String?
      content.each_line do |line|
        next unless line.includes?(REWRITE_ANNOTATION)

        if value = line.split(":", 2)[1]?
          return clean_template_path(value)
        end
      end
    end

    private def find_template_path_type(lines : Array(String), index : Int32) : String?
      offset = 1
      while offset <= 6
        candidate = lines[index + offset]?
        return unless candidate
        return if candidate.match(PATH_LINE)

        if match = candidate.match(PATH_TYPE_LINE)
          return clean_template_path_type(match[1])
        end
        offset += 1
      end
    end

    private def clean_template_path(value : String) : String?
      scalar = strip_yaml_comment(value).strip
      return "/" if scalar.empty?

      # The value as YAML reads it: `"/files/(\\w+)"` is `/files/(\w+)`.
      scalar = (YAML.parse(scalar).as_s? rescue nil) || strip_quotes(scalar) if scalar.starts_with?('"') || scalar.starts_with?('\'')
      return scalar if scalar.starts_with?("/")

      if quoted_path = scalar.match(/["'](\/[^"']*)["']/)
        return quoted_path[1]
      end

      "/" if scalar.includes?("{{")
    end

    private def clean_template_path_type(value : String) : String
      scalar = strip_yaml_comment(value).strip
      scalar = strip_quotes(scalar)
      return scalar if {"Exact", "Prefix", "ImplementationSpecific"}.includes?(scalar)

      if quoted_type = scalar.match(/["'](Exact|Prefix|ImplementationSpecific)["']/)
        return quoted_type[1]
      end

      DEFAULT_PATH_TYPE
    end

    private def clean_template_host(value : String) : String
      scalar = strip_yaml_comment(value).strip
      scalar = strip_quotes(scalar)
      return "" if scalar.includes?("{{")

      scalar
    end

    private def strip_yaml_comment(value : String) : String
      value.split("#", 2).first? || value
    end

    private def strip_quotes(value : String) : String
      stripped = value.strip
      if stripped.size >= 2
        first = stripped[0]
        last = stripped[stripped.size - 1]
        return stripped[1, stripped.size - 2] if (first == '"' && last == '"') || (first == '\'' && last == '\'')
      end

      stripped
    end
  end
end
