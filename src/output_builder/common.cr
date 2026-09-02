require "../ai_context/features"
require "../models/output_builder"
require "../models/endpoint"
require "./passive_scan"

@[Noir::OutputFormat(name: "plain", description: "Plain text (default)", order: 10)]
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

  # Parameter kinds drawn as an indented tree under a `○ <label>: ` header,
  # in emission order: `{param_type, label, name/value separator}`. Both are
  # green and both mark params the analyzer could not resolve; the separator
  # follows the wire syntax of the thing being printed (`Name: value` for a
  # header, `name=value` for a cookie).
  PARAM_TREE_FIELDS = [
    {"header", "headers", ": "},
    {"cookie", "cookies", "="},
  ]

  # Parameter kinds drawn as one cyan comma-joined line of names, in emission
  # order: `{param_type, label}`.
  PARAM_NAME_FIELDS = [
    # Intent extras (Bundle inputs, not part of the URI) read by a mobile
    # handler. Query params bake into the URL, so only "extra" is listed.
    {"extra", "extras"},
    # CLI inputs (protocol "cli"): named flags/options, positional arguments,
    # and consumed environment variables. HTTP endpoints have no params of
    # these types, so these rows only render for CLI endpoints.
    {"flag", "flags"},
    {"argument", "arguments"},
    {"env", "env"},
  ]

  # Parameter kinds already covered by the dedicated render sections above
  # (trees, named lists, query params baked into URL, or body payloads).
  HANDLED_PARAM_TYPES = Set{
    "header", "cookie", "query", "path",
    "extra", "flag", "argument", "env",
    "form", "json",
  }

  # Protocols the rest of the line already tells the reader about, so a badge
  # would only repeat it: `http` is the default and says nothing, the mobile
  # protocols drive the SCHEME/INTENT/UNIVERSAL/PROVIDER prefix, and `cli` is
  # spelled out by the `cli://` URL.
  SILENT_PROTOCOLS = Endpoint::MOBILE_PROTOCOLS | Endpoint::CLI_PROTOCOLS | Set{"http"}

  @ai_context_features : Set(String)? = nil

  # The plain report is the only format that frames itself — a heading over
  # the endpoint list, and the passive-scan findings appended below a second
  # one. Both used to sit in `NoirRunner#report`, which forced the runner to
  # special-case "is this the default format?" on either side of a dispatch
  # that otherwise treats every format alike.
  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult))
    logger.heading "Endpoint Results:"
    print(endpoints)
    return if passive_results.empty?

    # Separator through a builder, not `logger.puts`: the logger `exit(0)`s
    # the process on a broken pipe, so `noir scan . -P -o report.txt | head`
    # died on this one blank line and the `-o` file kept the endpoint list
    # but lost every finding. `ob_puts` marks stdout broken and keeps
    # filling the file. It also puts the blank line in `-o`, so the saved
    # report matches what stdout showed.
    ob_puts ""
    logger.heading "Passive Results:"
    OutputBuilderPassiveScan.new(@options).print(passive_results)
  end

  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      # Hues mirror the HTML report's method badges so the two outputs read
      # alike: QUERY is cyan there (`--m-query`), and safe-but-bodied, so it
      # gets its own hue rather than falling through to the uncolored default.
      r_method_color = case endpoint.method
                       when "GET"    then :green
                       when "POST"   then :blue
                       when "PUT"    then Colorize::Color256.new(208)
                       when "PATCH"  then Colorize::Color256.new(208)
                       when "DELETE" then :red
                       when "QUERY"  then :cyan
                       else               :default
                       end

      # Every string below is repo-derived and passes through
      # `escape_control_chars` before it is colorized, so an escape sequence
      # embedded in a route or a param name is shown rather than executed by
      # the reader's terminal. Colorize's own codes are added afterwards and
      # so are never touched.
      r_method = escape_control_chars(endpoint.method).colorize(r_method_color).toggle(@is_color)
      safe_url = escape_control_chars(baked[:url])

      r_buffer = String::Builder.new
      if mobile_label = MOBILE_PROTOCOL_LABELS[endpoint.protocol]?
        # intent:// is a synthetic scheme used so the optimizer treats
        # component names as absolute URLs; hide it in the text output.
        display_url = safe_url.lchop("intent://")
        r_label = mobile_label.colorize(:light_blue).toggle(@is_color)
        r_url = display_url.colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_label} #{r_url}"
      elsif endpoint.kind.empty?
        r_url = safe_url.colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_method} #{r_url}"
      else
        r_kind = "[#{escape_control_chars(endpoint.kind)}]".colorize(:light_magenta).toggle(@is_color)
        r_name = safe_url.lstrip('/').colorize(:light_yellow).toggle(@is_color)
        r_buffer << "\n#{r_method} #{r_kind} #{r_name}"
      end

      # `[]?` throughout: `config_initializer` seeds every key for CLI runs,
      # but a builder constructed with a partial options hash (specs, library
      # use) raised KeyError on the first endpoint. `any_to_bool` is untyped
      # and reads `nil` as false, matching each option's default.
      if any_to_bool(@options["status_codes"]?) || !@options["exclude_codes"]?.to_s.empty?
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

      # The protocol was visible for websockets only, so an AsyncAPI Kafka
      # topic, an MQTT channel, an AMQP queue, a gRPC/Connect method and an
      # nginx `listen 443 ssl` route all printed as if they were plain HTTP —
      # a distinction `-f json` and `-f markdown-table` both carry.
      if badge = protocol_badge(endpoint)
        r_protocol = "[#{escape_control_chars(badge)}]".colorize(:light_red).toggle(@is_color)
        r_buffer << " #{r_protocol}"
      end

      # `internal` marks an endpoint the application *calls* — a Spring Feign
      # or `@HttpExchange` declarative client — rather than one it serves.
      # Only the structured formats said so, so a client stub read here as
      # attack surface.
      if endpoint.internal
        r_internal = "[internal]".colorize(:dark_gray).toggle(@is_color)
        r_buffer << " #{r_internal}"
      end

      PARAM_TREE_FIELDS.each do |param_type, label, separator|
        entries = endpoint.params.select { |p| p.request_type == param_type }.map do |param|
          text = param.value.empty? ? param.name : "#{param.name}#{separator}#{param.value}"
          # Only these two rows flag unresolved params; the form-body tree
          # below is drawn the same way but deliberately omits the marker.
          text += " [unresolved]" if param.tags.any? { |t| t.name == "unresolved" }
          text
        end
        append_tree_field r_buffer, label, entries, :light_green
      end

      if !baked[:path_param].empty?
        append_field r_buffer, "path", baked[:path_param].join(", "), :cyan
      end

      if endpoint_metadata = endpoint.metadata
        MOBILE_METADATA_KEYS.each do |key|
          if value = endpoint_metadata[key]?
            append_field r_buffer, key, value, :cyan
          end
        end
      end

      PARAM_NAME_FIELDS.each do |param_type, label|
        selected = endpoint.params.select { |p| p.request_type == param_type }
        append_field r_buffer, label, selected.map(&.name).join(", "), :cyan unless selected.empty?
      end

      # Same tree shape as headers/cookies but cyan, and with no
      # "[unresolved]" marker even on params carrying that tag.
      form_entries = endpoint.params.select { |p| p.request_type == "form" }.map do |param|
        param.value.empty? ? param.name : "#{param.name}=#{param.value}"
      end

      if baked[:body_type] == "form"
        append_tree_field r_buffer, "body", form_entries, :cyan
      else
        append_field r_buffer, "body", baked[:body], :cyan unless baked[:body].empty?
        # An endpoint whose handler reads both a JSON body and form fields
        # (`c.Request.PostFormValue` next to `c.BindJSON`, say) has params of
        # both kinds, but `bake_endpoint` has one `body` slot and JSON wins
        # it — so every form param on such an endpoint was dropped from this
        # report while `-f json` and `-f markdown-table` still listed it.
        # Render them under their own type name, the same convention the
        # leftover-bucket rows below use, rather than a second "body" row.
        append_tree_field r_buffer, "form", form_entries, :cyan
      end

      # Anything left is still a named input the endpoint reads (multipart
      # `file` fields, `xml` bodies, websocket parameters, etc.) that would
      # otherwise be silently dropped. Render remaining buckets by type name.
      remaining_params = endpoint.params.reject { |p| HANDLED_PARAM_TYPES.includes?(p.request_type) }
      remaining_by_type = Hash(String, Array(String)).new
      remaining_params.each do |param|
        type = param.request_type
        remaining_by_type[type] ||= [] of String
        remaining_by_type[type] << param.name
      end

      remaining_by_type.each do |type, names|
        append_field r_buffer, type, names.join(", "), :cyan unless names.empty?
      end

      tags = baked[:tags].reject { |t| t == "unresolved" } # will handle unresolved directly in the logs
      endpoint.tags.each do |tag|
        tags << tag.name.to_s
      end

      # Deduped by name, the way `-f only-tag` already does it. `add_tag`
      # dedupes by (name, tagger), so one endpoint legitimately carries three
      # distinct `graphql-return` tags from three analyzers — and this row,
      # which prints names only, rendered them as "graphql-return
      # graphql-return graphql-return". 45 rows in the fixture tree repeated a
      # name they had nothing left to tell apart by.
      tags = tags.uniq

      # Space-joined, unlike every other multi-value row above, which uses ", ".
      append_field r_buffer, "tags", tags.join(" "), :light_magenta unless tags.empty?

      # Show technology only if include_techs flag is set
      if any_to_bool(@options["include_techs"]?) && endpoint.details.technology
        append_field r_buffer, "tech", endpoint.details.technology.to_s, :light_blue
      end

      if any_to_bool(@options["include_path"]?)
        details = endpoint.details
        if details.code_paths && !details.code_paths.empty?
          details.code_paths.each do |code_path|
            location = code_path.line.nil? ? code_path.path : "#{code_path.path} (line #{code_path.line})"
            # The one row printed without color; every sibling colorizes.
            append_field r_buffer, "file", location, nil
          end
        end
      end

      context = endpoint.ai_context
      if any_to_bool(@options["ai_context"]?) && !context.nil?
        unless context.empty?
          features = ai_context_feature_filter
          # {feature name, printed label, entries}. The two names differ for
          # callees on purpose: the flag is `--ai-context callee` (singular),
          # the printed block is "callees".
          blocks = {
            {"guards", "guards", context.guards},
            {"callee", "callees", context.callees},
            {"sources", "sources", context.sources},
            {"sinks", "sinks", context.sinks},
            {"validators", "validators", context.validators},
            {"signals", "signals", context.signals},
          }

          if blocks.any? { |feature, _, entries| features.includes?(feature) && !entries.empty? }
            # No trailing space after the colon here, unlike every `append_field`
            # row — the entries start on their own lines two levels deeper.
            r_buffer << "\n  ○ ai_context:"
            blocks.each do |feature, label, entries|
              append_ai_context_block(r_buffer, label, entries) if features.includes?(feature)
            end
          end
        end
      elsif any_to_bool(@options["include_callee"]?) && !endpoint.callees.empty?
        # `format_noir_callee`, the same renderer the OpenAPI/Postman
        # descriptions use, so the location is spelled one way everywhere.
        # This row used to build its own `name (line N)` and drop
        # `callee.path` — and a callee almost always lives in the handler
        # file, not the route file printed on the `file:` row just above, so
        # a bare line number pointed the reader at the wrong file.
        callee_entries = endpoint.callees.map { |callee| format_noir_callee(callee) }
        append_tree_field r_buffer, "callees", callee_entries, :light_cyan
      end

      ob_puts r_buffer.to_s
    end
  end

  # The badge to print after the endpoint line, or nil when the protocol adds
  # nothing. `ws` keeps the spelled-out "websocket" it has always had.
  private def protocol_badge(endpoint : Endpoint) : String?
    protocol = endpoint.protocol
    return if SILENT_PROTOCOLS.includes?(protocol)

    protocol == "ws" ? "websocket" : protocol
  end

  # One `○ <label>: <value>` row under the endpoint line. `color` is nil for
  # the one row that is printed uncolorized.
  private def append_field(r_buffer : String::Builder, label : String, value : String, color : Symbol?)
    value = escape_control_chars(value)
    r_buffer << "\n  ○ " << escape_control_chars(label) << ": "
    if color
      r_buffer << value.colorize(color).toggle(@is_color)
    else
      r_buffer << value
    end
  end

  # A `○ <label>: ` row whose values hang below it as an indented tree. Note
  # the header keeps its trailing space even though nothing follows it on
  # that line.
  private def append_tree_field(r_buffer : String::Builder, label : String, entries : Array(String), color : Symbol)
    return if entries.empty?

    r_buffer << "\n  ○ " << escape_control_chars(label) << ": "
    entries.each_with_index do |entry, index|
      prefix = index == entries.size - 1 ? "└── " : "├── "
      r_buffer << "\n    " << "#{prefix}#{escape_control_chars(entry)}".colorize(color).toggle(@is_color)
    end
  end

  # Returns the set of AI-context category names that should be emitted.
  # An empty/unset `ai_context_features` option means "all categories".
  #
  # Memoized: the option cannot change mid-render, but this is read
  # inside the per-endpoint loop, so it was parsing the option string and
  # allocating a fresh Set once per endpoint.
  private def ai_context_feature_filter : Set(String)
    @ai_context_features ||= NoirAIContext.parse_feature_set(@options["ai_context_features"]?.try(&.to_s) || "")
  end

  private def append_ai_context_block(r_buffer : String::Builder, label : String, entries : Array(AIContextEntry))
    return if entries.empty?

    r_buffer << "\n    - #{label}:"
    entries.each do |entry|
      r_entry = escape_control_chars(format_ai_context_entry(entry)).colorize(:light_cyan).toggle(@is_color)
      r_buffer << "\n      * #{r_entry}"
    end
  end
end
