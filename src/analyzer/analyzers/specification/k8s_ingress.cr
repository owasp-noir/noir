require "../../../models/analyzer"

module Analyzer::Specification
  class K8sIngress < Analyzer
    METHOD_ANY         = "ANY"
    REWRITE_ANNOTATION = "nginx.ingress.kubernetes.io/rewrite-target"

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
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_doc(doc : YAML::Any, details : Details)
      root = doc.as_h?
      return unless root

      kind = root[YAML::Any.new("kind")]?.try(&.as_s?)
      return unless kind == "Ingress"

      api_version = root[YAML::Any.new("apiVersion")]?.try(&.as_s?)
      return unless api_version && api_version.starts_with?("networking.k8s.io/")

      metadata = root[YAML::Any.new("metadata")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      annotations = metadata[YAML::Any.new("annotations")]?.try(&.as_h?) || {} of YAML::Any => YAML::Any
      rewrite_target = annotations[YAML::Any.new(REWRITE_ANNOTATION)]?.try(&.as_s?)

      spec = root[YAML::Any.new("spec")]?.try(&.as_h?)
      return unless spec

      tls_hosts = collect_tls_hosts(spec[YAML::Any.new("tls")]?)
      rules = spec[YAML::Any.new("rules")]?.try(&.as_a?) || [] of YAML::Any
      rules.each { |rule| process_rule(rule, tls_hosts, rewrite_target, details) }
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
        next if path.empty?

        path_type = path_h[YAML::Any.new("pathType")]?.try(&.as_s?) || "ImplementationSpecific"
        emit_endpoint(path, path_type, host, tls_hosts, details)

        if rewrite_target && !rewrite_target.empty?
          rewritten = strip_capture_groups(rewrite_target)
          if rewritten != path
            emit_endpoint(rewritten, path_type, host, tls_hosts, details, "rewrite")
          end
        end
      end
    end

    private def emit_endpoint(path : String, path_type : String, host : String, tls_hosts : Set(String), details : Details, origin : String = "rule")
      endpoint = Endpoint.new(path, METHOD_ANY, details)
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
  end
end
