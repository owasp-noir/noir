require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderCommon < OutputBuilder
  # Mobile entry points keep method = "GET" internally; the protocol
  # carries the real semantics and drives the display prefix.
  MOBILE_PROTOCOL_LABELS = {
    "mobile-scheme"    => "SCHEME",
    "android-intent"   => "INTENT",
    "universal-link"   => "UNIVERSAL",
    "android-provider" => "PROVIDER",
  }

  # Fixed order so plain output is deterministic. The protocol drives the
  # prefix and "path" comes from path params, so neither is repeated here.
  # component_type/exported/explicit appear on explicit-intent (filter-less
  # exported) and provider surfaces; the *_permission / grant_uri_permissions /
  # path_permissions keys only on providers. Absent keys are skipped per
  # endpoint.
  MOBILE_METADATA_KEYS = ["via", "query", "action", "category", "host", "package",
                          "component_type", "exported", "explicit", "permission",
                          "read_permission", "write_permission", "grant_uri_permissions",
                          "path_permissions", "extras"]

  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      r_method_color = case endpoint.method
                       when "GET"    then :green
                       when "POST"   then :blue
                       when "PUT"    then Colorize::Color256.new(208)
                       when "PATCH"  then Colorize::Color256.new(208)
                       when "DELETE" then :red
                       else               :default
                       end

      r_method = endpoint.method.colorize(r_method_color).toggle(@is_color)

      r_buffer = String::Builder.new
      if mobile_label = MOBILE_PROTOCOL_LABELS[endpoint.protocol]?
        # intent:// is a synthetic scheme used so the optimizer treats
        # component names as absolute URLs; hide it in the text output.
        display_url = baked[:url].lchop("intent://")
        r_label = mobile_label.colorize(:light_blue).toggle(@is_color)
        r_url = display_url.colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_label} #{r_url}"
      elsif endpoint.kind.empty?
        r_url = baked[:url].colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_method} #{r_url}"
      else
        r_kind = "[#{endpoint.kind}]".colorize(:light_magenta).toggle(@is_color)
        r_name = baked[:url].lstrip('/').colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_method} #{r_kind} #{r_name}"
      end

      if any_to_bool(@options["status_codes"]) || !@options["exclude_codes"].to_s.empty?
        status_color = :light_green
        status_code = endpoint.details.status_code
        if status_code
          if status_code >= 500
            status_color = :light_magenta
          elsif status_code >= 400
            status_color = :light_red
          elsif status_code >= 300
            status_color = :cyan
          end
        else
          status_code = "error"
          status_color = :light_red
        end

        r_buffer << " [#{status_code}]".to_s.colorize(status_color).toggle(@is_color).to_s
      end

      if endpoint.protocol == "ws"
        r_ws = "[websocket]".colorize(:light_red).toggle(@is_color)
        r_buffer << " #{r_ws}"
      end

      header_params = endpoint.params.select { |p| p.param_type == "header" }
      if header_params.size > 0
        r_buffer << "\n  ○ headers: "
        header_params.each_with_index do |param, index|
          prefix = index == header_params.size - 1 ? "└── " : "├── "
          label = param.value.empty? ? param.name : "#{param.name}: #{param.value}"
          label += " [unresolved]" if param.tags.any? { |t| t.name == "unresolved" }
          r_header = "#{prefix}#{label}".colorize(:light_green).toggle(@is_color)
          r_buffer << "\n    #{r_header}"
        end
      end

      cookie_params = endpoint.params.select { |p| p.param_type == "cookie" }
      if cookie_params.size > 0
        r_buffer << "\n  ○ cookies: "
        cookie_params.each_with_index do |param, index|
          prefix = index == cookie_params.size - 1 ? "└── " : "├── "
          label = param.value.empty? ? param.name : "#{param.name}=#{param.value}"
          label += " [unresolved]" if param.tags.any? { |t| t.name == "unresolved" }
          r_cookie = "#{prefix}#{label}".colorize(:light_green).toggle(@is_color)
          r_buffer << "\n    #{r_cookie}"
        end
      end

      if baked[:path_param].size > 0
        r_path_param = baked[:path_param].join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ path: #{r_path_param}"
      end

      if endpoint_metadata = endpoint.metadata
        MOBILE_METADATA_KEYS.each do |key|
          if value = endpoint_metadata[key]?
            r_value = value.colorize(:cyan).toggle(@is_color)
            r_buffer << "\n  ○ #{key}: #{r_value}"
          end
        end
      end

      # Intent extras (Bundle inputs, not part of the URI) read by a mobile
      # handler. Query params bake into the URL, so only "extra" is listed.
      extra_params = endpoint.params.select { |p| p.param_type == "extra" }
      if extra_params.size > 0
        r_extras = extra_params.map(&.name).join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ extras: #{r_extras}"
      end

      # CLI inputs (protocol "cli"): named flags/options, positional
      # arguments, and consumed environment variables. HTTP endpoints have
      # no params of these types, so these sections only render for CLI
      # endpoints.
      flag_params = endpoint.params.select { |p| p.param_type == "flag" }
      if flag_params.size > 0
        r_flags = flag_params.map(&.name).join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ flags: #{r_flags}"
      end

      argument_params = endpoint.params.select { |p| p.param_type == "argument" }
      if argument_params.size > 0
        r_arguments = argument_params.map(&.name).join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ arguments: #{r_arguments}"
      end

      env_params = endpoint.params.select { |p| p.param_type == "env" }
      if env_params.size > 0
        r_env = env_params.map(&.name).join(", ").colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ env: #{r_env}"
      end

      if baked[:body_type] == "form"
        form_params = endpoint.params.select { |p| p.param_type == "form" }
        unless form_params.empty?
          r_buffer << "\n  ○ body: "
          form_params.each_with_index do |param, index|
            prefix = index == form_params.size - 1 ? "└── " : "├── "
            label = param.value.empty? ? param.name : "#{param.name}=#{param.value}"
            r_buffer << "\n    #{("#{prefix}#{label}").colorize(:cyan).toggle(@is_color)}"
          end
        end
      elsif !baked[:body].empty?
        r_body = baked[:body].colorize(:cyan).toggle(@is_color)
        r_buffer << "\n  ○ body: #{r_body}"
      end

      tags = baked[:tags].reject { |t| t == "unresolved" } # will handle unresolved directly in the logs
      endpoint.tags.each do |tag|
        tags << tag.name.to_s
      end

      if tags.size > 0
        r_tags = tags.join(" ").colorize(:light_magenta).toggle(@is_color)
        r_buffer << "\n  ○ tags: #{r_tags}"
      end

      # Show technology only if include_techs flag is set
      if any_to_bool(@options["include_techs"]) && endpoint.details.technology
        r_tech = endpoint.details.technology.to_s.colorize(:light_blue).toggle(@is_color)
        r_buffer << "\n  ○ tech: #{r_tech}"
      end

      if any_to_bool(@options["include_path"])
        details = endpoint.details
        if details.code_paths && !details.code_paths.empty?
          details.code_paths.each do |code_path|
            if code_path.line.nil?
              r_buffer << "\n  ○ file: #{code_path.path}"
            else
              r_buffer << "\n  ○ file: #{code_path.path} (line #{code_path.line})"
            end
          end
        end
      end

      context = endpoint.ai_context
      if any_to_bool(@options["ai_context"]) && !context.nil?
        unless context.empty?
          features = ai_context_feature_filter
          visible = (features.includes?("guards") && !context.guards.empty?) ||
                    (features.includes?("callee") && !context.callees.empty?) ||
                    (features.includes?("sources") && !context.sources.empty?) ||
                    (features.includes?("sinks") && !context.sinks.empty?) ||
                    (features.includes?("validators") && !context.validators.empty?) ||
                    (features.includes?("signals") && !context.signals.empty?)

          if visible
            r_buffer << "\n  ○ ai_context:"
            append_ai_context_block(r_buffer, "guards", context.guards) if features.includes?("guards")
            append_ai_context_block(r_buffer, "callees", context.callees) if features.includes?("callee")
            append_ai_context_block(r_buffer, "sources", context.sources) if features.includes?("sources")
            append_ai_context_block(r_buffer, "sinks", context.sinks) if features.includes?("sinks")
            append_ai_context_block(r_buffer, "validators", context.validators) if features.includes?("validators")
            append_ai_context_block(r_buffer, "signals", context.signals) if features.includes?("signals")
          end
        end
      elsif any_to_bool(@options["include_callee"]) && !endpoint.callees.empty?
        r_buffer << "\n  ○ callees: "
        endpoint.callees.each_with_index do |callee, index|
          prefix = index == endpoint.callees.size - 1 ? "└── " : "├── "
          label = callee.line ? "#{callee.name} (line #{callee.line})" : callee.name
          r_callee = "#{prefix}#{label}".colorize(:light_cyan).toggle(@is_color)
          r_buffer << "\n    #{r_callee}"
        end
      end

      ob_puts r_buffer.to_s
    end
  end

  # Returns the set of AI-context category names that should be emitted.
  # An empty/unset `ai_context_features` option means "all categories".
  private def ai_context_feature_filter : Set(String)
    all = Set{"guards", "callee", "sources", "sinks", "validators", "signals"}
    raw = @options["ai_context_features"]?.try(&.to_s) || ""
    return all if raw.empty?

    filtered = Set(String).new
    raw.split(',').each do |feature|
      f = feature.strip
      next if f.empty?
      return all if f == "all"
      filtered << f
    end
    filtered
  end

  private def append_ai_context_block(r_buffer : String::Builder, label : String, entries : Array(AIContextEntry))
    return if entries.empty?

    r_buffer << "\n    - #{label}:"
    entries.each do |entry|
      r_entry = format_ai_context_entry(entry).colorize(:light_cyan).toggle(@is_color)
      r_buffer << "\n      * #{r_entry}"
    end
  end

  private def format_ai_context_entry(entry : AIContextEntry) : String
    label = "#{entry.kind}: #{entry.name}"
    label += " [#{entry.source}]" if entry.source
    label += " (#{entry.path}:#{entry.line})" if entry.path && entry.line
    label += " (#{entry.path})" if entry.path && entry.line.nil?
    label += " (line #{entry.line})" if entry.path.nil? && entry.line
    label += " - #{entry.description}" if entry.description
    label += " :: #{entry.snippet}" if entry.snippet
    label
  end
end
