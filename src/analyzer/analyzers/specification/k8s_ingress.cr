require "../../../models/analyzer"

module Analyzer::Specification
  class K8sIngress < Analyzer
    DEFAULT_METHOD     = "GET"
    REWRITE_ANNOTATION = "nginx.ingress.kubernetes.io/rewrite-target"
    DEFAULT_PATH_TYPE  = "ImplementationSpecific"
    API_VERSION_LINE   = /(?m)^[ \t-]*apiVersion:\s*["']?(?:networking\.k8s\.io\/[^"'\s#]+|extensions\/v1beta1)["']?\s*(?:#.*)?$/
    KIND_LINE          = /(?m)^[ \t-]*kind:\s*["']?Ingress["']?\s*(?:#.*)?$/
    PATH_LINE          = /^[ \t-]*path:\s*(.*)$/
    PATH_TYPE_LINE     = /^[ \t-]*pathType:\s*(.*)$/
    HOST_LINE          = /^[ \t-]*host:\s*(.*)$/

    def analyze
      spec_files = CodeLocator.instance.all("k8s-ingress-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          YAML.parse_all(content).each { |doc| process_doc(doc, details) }
        rescue e
          @logger.debug "Exception processing #{path}, falling back to tolerant Ingress template extraction"
          @logger.debug_sub e
          process_template(content, details)
        end
      end

      @result
    end

    private def process_doc(doc : YAML::Any, details : Details)
      root = doc.as_h?
      return unless root

      kind = root[YAML::Any.new("kind")]?.try(&.as_s?)
      if kind == "List"
        items = root[YAML::Any.new("items")]?.try(&.as_a?) || [] of YAML::Any
        items.each { |item| process_doc(item, details) }
        return
      end

      return unless kind == "Ingress"

      api_version = root[YAML::Any.new("apiVersion")]?.try(&.as_s?)
      return unless supported_api_version?(api_version)

      metadata = root[YAML::Any.new("metadata")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      annotations = metadata[YAML::Any.new("annotations")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      rewrite_target = annotations[YAML::Any.new(REWRITE_ANNOTATION)]?.try(&.as_s?)

      spec = root[YAML::Any.new("spec")]?.try(&.as_h?)
      return unless spec

      tls_hosts = collect_tls_hosts(spec[YAML::Any.new("tls")]?)
      process_default_backend(spec[YAML::Any.new("defaultBackend")]?, tls_hosts, details)

      rules = spec[YAML::Any.new("rules")]?.try(&.as_a?) || [] of YAML::Any
      rules.each { |rule| process_rule(rule, tls_hosts, rewrite_target, details) }
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

    private def process_rule(rule : YAML::Any, tls_hosts : Set(String), rewrite_target : String?, details : Details)
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
        emit_endpoint(path, path_type, host, tls_hosts, details)

        if rewrite_target && !rewrite_target.empty?
          rewritten = strip_capture_groups(rewrite_target)
          if rewritten != path
            emit_endpoint(rewritten, path_type, host, tls_hosts, details, "rewrite")
          end
        end
      end
    end

    private def process_default_backend(default_backend : YAML::Any?, tls_hosts : Set(String), details : Details)
      return unless backend_present?(default_backend)

      emit_endpoint("/", DEFAULT_PATH_TYPE, "", tls_hosts, details, "default-backend")
    end

    private def backend_present?(backend : YAML::Any?) : Bool
      backend.try(&.as_h?) != nil
    end

    private def emit_endpoint(path : String, path_type : String, host : String, tls_hosts : Set(String), details : Details, origin : String = "rule")
      endpoint = Endpoint.new(path, DEFAULT_METHOD, details)
      endpoint.add_tag(Tag.new("ingress-path-type", path_type.downcase, "k8s_ingress_analyzer"))
      endpoint.add_tag(Tag.new("ingress-host", host, "k8s_ingress_analyzer")) unless host.empty?
      endpoint.add_tag(Tag.new("ingress-source", origin, "k8s_ingress_analyzer"))
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
        emit_template_endpoint(path, path_type, host, tls_hosts, details, emitted)

        if rewrite_target && !rewrite_target.empty?
          rewritten = strip_capture_groups(rewrite_target)
          emit_template_endpoint(rewritten, path_type, host, tls_hosts, details, emitted, "rewrite") unless rewritten == path
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

      scalar = strip_quotes(scalar)
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
