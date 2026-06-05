require "../../../models/analyzer"

module Analyzer::Specification
  # Extracts the externally reachable surface described by a Kamal
  # (https://kamal-deploy.org) `config/deploy.yml`. The `proxy` block
  # declares the hosts kamal-proxy serves, the path prefixes it forwards,
  # and the health endpoint it probes on every deploy — all of which are
  # live HTTP routes worth inventorying.
  class Kamal < Analyzer
    DEFAULT_HEALTHCHECK_PATH = "/up"
    APP_METHOD               = "ANY"
    HEALTHCHECK_METHOD       = "GET"

    def analyze
      spec_files = CodeLocator.instance.all("kamal-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          process_config(YAML.parse(content), details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_config(data : YAML::Any, details : Details)
      root = data.as_h?
      return unless root

      proxy = root[YAML::Any.new("proxy")]?.try(&.as_h?)
      return unless proxy

      service = root[YAML::Any.new("service")]?.try(&.as_s?)
      hosts = collect_hosts(proxy)
      protocol = ssl_enabled?(proxy) ? "https" : "http"
      app_port = scalar_to_s(proxy[YAML::Any.new("app_port")]?)

      # The app's served surface: each configured path prefix, or the site
      # root when the proxy forwards every request to the app.
      collect_path_prefixes(proxy).each do |prefix|
        emit(prefix, APP_METHOD, "proxy", hosts, protocol, service, app_port, details)
      end

      # kamal-proxy probes the app's health endpoint (default `/up`) on
      # every deploy, so it is always a live, reachable route. It is
      # configured independently of `path_prefix`, so emit it verbatim
      # rather than composing it under a prefix.
      emit(healthcheck_path(proxy), HEALTHCHECK_METHOD, "healthcheck", hosts, protocol, service, app_port, details)
    end

    private def emit(path : String, method : String, origin : String, hosts : Array(String),
                     protocol : String, service : String?, app_port : String?, details : Details)
      endpoint = Endpoint.new(normalize_path(path), method, details)
      endpoint.protocol = protocol
      endpoint.add_tag(Tag.new("kamal-source", origin, "kamal_analyzer"))
      # `add_tag` dedupes on (name, tagger), so every host is folded into a
      # single comma-joined tag rather than emitted as repeated tags.
      endpoint.add_tag(Tag.new("kamal-host", hosts.join(", "), "kamal_analyzer")) unless hosts.empty?
      endpoint.add_tag(Tag.new("kamal-service", service, "kamal_analyzer")) if service && !service.empty?
      endpoint.add_tag(Tag.new("kamal-app-port", app_port, "kamal_analyzer")) if app_port && !app_port.empty?
      @result << endpoint
    end

    private def collect_hosts(proxy : Hash(YAML::Any, YAML::Any)) : Array(String)
      hosts = [] of String

      if host = proxy[YAML::Any.new("host")]?.try(&.as_s?)
        hosts << host unless host.empty?
      end

      if list = proxy[YAML::Any.new("hosts")]?.try(&.as_a?)
        list.each do |entry|
          if h = entry.as_s?
            hosts << h unless h.empty?
          end
        end
      end

      hosts.uniq!
      hosts
    end

    private def collect_path_prefixes(proxy : Hash(YAML::Any, YAML::Any)) : Array(String)
      prefixes = [] of String

      # `path_prefix` accepts a single value or a comma-separated list.
      if raw = proxy[YAML::Any.new("path_prefix")]?.try(&.as_s?)
        raw.split(',').each do |part|
          stripped = part.strip
          prefixes << stripped unless stripped.empty?
        end
      end

      if list = proxy[YAML::Any.new("path_prefixes")]?.try(&.as_a?)
        list.each do |entry|
          if p = entry.as_s?
            prefixes << p unless p.empty?
          end
        end
      end

      prefixes.uniq!
      # No prefix set means the proxy forwards every path to the app, so
      # the served surface is rooted at `/`.
      prefixes.empty? ? ["/"] : prefixes
    end

    private def healthcheck_path(proxy : Hash(YAML::Any, YAML::Any)) : String
      healthcheck = proxy[YAML::Any.new("healthcheck")]?.try(&.as_h?)
      if healthcheck
        if path = healthcheck[YAML::Any.new("path")]?.try(&.as_s?)
          return path unless path.empty?
        end
      end
      DEFAULT_HEALTHCHECK_PATH
    end

    # `ssl` is either a boolean (`ssl: true`) or a hash carrying custom
    # certificate material — both mean HTTPS is being terminated.
    private def ssl_enabled?(proxy : Hash(YAML::Any, YAML::Any)) : Bool
      ssl = proxy[YAML::Any.new("ssl")]?
      return false if ssl.nil?
      return true if ssl.as_bool? == true
      !ssl.as_h?.nil?
    end

    private def scalar_to_s(value : YAML::Any?) : String?
      return if value.nil?
      if s = value.as_s?
        return s.empty? ? nil : s
      end
      if i = value.as_i64?
        return i.to_s
      end
      nil
    end

    private def normalize_path(path : String) : String
      cleaned = path.strip
      return "/" if cleaned.empty?
      cleaned.starts_with?('/') ? cleaned : "/#{cleaned}"
    end
  end
end
