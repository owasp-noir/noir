require "../../../models/analyzer"

module Analyzer::Specification
  # AsyncAPI 2.x / 3.x analyzer.
  #
  # Maps event-driven channels to endpoints:
  #   * 2.x — `channels.<name>.{publish,subscribe}` → one endpoint per
  #     (channel, operation). Operation becomes the method-like field
  #     ("PUBLISH" / "SUBSCRIBE"). Message payload schema becomes the
  #     body shape.
  #   * 3.x — `operations.<id>` with `action: send|receive` referencing
  #     a `channels.<name>` entry. Method becomes "SEND" / "RECEIVE".
  #     The channel's `address` (or the channel key as fallback) is the
  #     path.
  #
  # The first server's `protocol` (kafka, mqtt, ws, amqp, nats, http, …)
  # is surfaced on the endpoint so DAST consumers can route accordingly.
  class AsyncApi < Analyzer
    # Operation keys on `channels` entries (2.x).
    OPERATIONS_2X = {"publish", "subscribe"}

    def analyze
      locator = CodeLocator.instance
      jsons = locator.all("asyncapi-json")
      yamls = locator.all("asyncapi-yaml")

      if jsons.is_a?(Array(String))
        jsons.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          process_json(JSON.parse(content), details, path)
        rescue e
          @logger.debug "Exception parsing AsyncAPI #{path}"
          @logger.debug_sub e
        end
      end

      if yamls.is_a?(Array(String))
        yamls.each do |path|
          next unless File.exists?(path)
          details = Details.new(PathInfo.new(path))
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          process_yaml(YAML.parse(content), details, path)
        rescue e
          @logger.debug "Exception parsing AsyncAPI #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    # --- JSON path ------------------------------------------------------

    private def process_json(root : JSON::Any, details : Details, source : String)
      version = root["asyncapi"]?.try(&.as_s?) || ""
      protocol = first_server_protocol_json(root)

      if version.starts_with?("3.")
        process_v3_json(root, protocol, details, source)
      else
        process_v2_json(root, protocol, details, source)
      end
    end

    private def first_server_protocol_json(root : JSON::Any) : String?
      servers = root["servers"]?.try(&.as_h?)
      return unless servers
      servers.each_value do |server|
        if proto = server["protocol"]?.try(&.as_s?)
          return proto
        end
      end
      nil
    end

    private def process_v2_json(root : JSON::Any, protocol : String?, details : Details, source : String)
      channels = root["channels"]?.try(&.as_h?)
      return unless channels
      channels.each do |channel_name, channel_obj|
        next unless channel_h = channel_obj.as_h?
        OPERATIONS_2X.each do |op|
          next unless op_obj = channel_h[op]?
          params = [] of Param
          if message = op_obj["message"]?
            collect_message_payload_json(root, message, params)
          end
          push_endpoint(channel_name.to_s, op.upcase, params, protocol, details)
        end
      end
    end

    private def process_v3_json(root : JSON::Any, protocol : String?, details : Details, source : String)
      channels = root["channels"]?.try(&.as_h?) || {} of String => JSON::Any
      operations = root["operations"]?.try(&.as_h?)
      return unless operations

      operations.each do |_, op_obj|
        next unless op_h = op_obj.as_h?

        action = op_h["action"]?.try(&.as_s?) || ""
        method = case action
                 when "send"    then "SEND"
                 when "receive" then "RECEIVE"
                 else                action.upcase
                 end

        channel_path = resolve_channel_path_json(root, op_h["channel"]?, channels)
        next if channel_path.empty?

        params = [] of Param
        if messages = op_h["messages"]?.try(&.as_a?)
          messages.each { |m| collect_message_payload_json(root, m, params) }
        end

        push_endpoint(channel_path, method, params, protocol, details)
      end
    end

    private def resolve_channel_path_json(root : JSON::Any, channel_ref : JSON::Any?, channels : Hash(String, JSON::Any)) : String
      return "" unless channel_ref && channel_ref.as_h?
      if ref = channel_ref["$ref"]?.try(&.as_s?)
        # Try to read `address` from the referenced channel, else
        # use the last path segment as the channel key.
        if resolved = resolve_ref_json(root, ref)
          if addr = resolved["address"]?.try(&.as_s?)
            return addr
          end
        end
        return ref.split('/').last
      end
      if addr = channel_ref["address"]?.try(&.as_s?)
        return addr
      end
      ""
    end

    private def collect_message_payload_json(root : JSON::Any, message : JSON::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      msg = message
      # `msg` may be reassigned to a $ref target that resolves to a scalar;
      # gate every subscript on as_h? so a non-object never raises "Expected Hash".
      while msg.as_h? && (ref = msg["$ref"]?.try(&.as_s?))
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          msg = resolved
        else
          return
        end
      end
      if msg.as_h? && (payload = msg["payload"]?)
        collect_schema_props_json(root, payload, "json", params)
      end
    end

    private def collect_schema_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # A scalar schema (e.g. JSON-Schema boolean, or an allOf element `true`)
      # makes the `["..."]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref = schema["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          collect_schema_props_json(root, resolved, param_type, params, seen)
        end
        return
      end

      if props = schema["properties"]?.try(&.as_h?)
        props.each do |name, _|
          params << Param.new(name.to_s, "", param_type)
        end
      end

      if all_of = schema["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end
    end

    private def resolve_ref_json(root : JSON::Any, ref : String) : JSON::Any?
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

    # --- YAML path ------------------------------------------------------

    private def process_yaml(root : YAML::Any, details : Details, source : String)
      version = root[YAML::Any.new("asyncapi")]?.try(&.as_s?) || ""
      protocol = first_server_protocol_yaml(root)

      if version.starts_with?("3.")
        process_v3_yaml(root, protocol, details, source)
      else
        process_v2_yaml(root, protocol, details, source)
      end
    end

    private def first_server_protocol_yaml(root : YAML::Any) : String?
      servers_node = root[YAML::Any.new("servers")]?
      return unless servers_node
      servers = servers_node.as_h?
      return unless servers
      servers.each_value do |server|
        if proto_node = server[YAML::Any.new("protocol")]?
          if proto = proto_node.as_s?
            return proto
          end
        end
      end
      nil
    end

    private def process_v2_yaml(root : YAML::Any, protocol : String?, details : Details, source : String)
      channels_node = root[YAML::Any.new("channels")]?
      return unless channels_node
      channels = channels_node.as_h?
      return unless channels
      channels.each do |channel_name, channel_obj|
        next unless channel_h = channel_obj.as_h?
        OPERATIONS_2X.each do |op|
          next unless op_obj = channel_h[YAML::Any.new(op)]?
          params = [] of Param
          if message_node = op_obj[YAML::Any.new("message")]?
            collect_message_payload_yaml(root, message_node, params)
          end
          push_endpoint(channel_name.to_s, op.upcase, params, protocol, details)
        end
      end
    end

    private def process_v3_yaml(root : YAML::Any, protocol : String?, details : Details, source : String)
      operations_node = root[YAML::Any.new("operations")]?
      return unless operations_node
      operations = operations_node.as_h?
      return unless operations

      operations.each do |_, op_obj|
        next unless op_h = op_obj.as_h?

        action = op_h[YAML::Any.new("action")]?.try(&.as_s?) || ""
        method = case action
                 when "send"    then "SEND"
                 when "receive" then "RECEIVE"
                 else                action.upcase
                 end

        channel_ref = op_h[YAML::Any.new("channel")]?
        channel_path = resolve_channel_path_yaml(root, channel_ref)
        next if channel_path.empty?

        params = [] of Param
        if messages_node = op_h[YAML::Any.new("messages")]?
          if messages = messages_node.as_a?
            messages.each { |m| collect_message_payload_yaml(root, m, params) }
          end
        end

        push_endpoint(channel_path, method, params, protocol, details)
      end
    end

    private def resolve_channel_path_yaml(root : YAML::Any, channel_ref : YAML::Any?) : String
      return "" unless channel_ref && channel_ref.as_h?
      if ref_node = channel_ref[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          if resolved = resolve_ref_yaml(root, ref)
            if addr_node = resolved[YAML::Any.new("address")]?
              if addr = addr_node.as_s?
                return addr
              end
            end
          end
          return ref.split('/').last
        end
      end
      if addr_node = channel_ref[YAML::Any.new("address")]?
        if addr = addr_node.as_s?
          return addr
        end
      end
      ""
    end

    private def collect_message_payload_yaml(root : YAML::Any, message : YAML::Any, params : Array(Param), seen : Set(String) = Set(String).new)
      msg = message
      # `msg` may be reassigned to a $ref target that resolves to a scalar;
      # gate every subscript on as_h? so a non-object never raises "Expected Hash".
      while msg.as_h? && (ref_node = msg[YAML::Any.new("$ref")]?)
        ref = ref_node.as_s?
        break unless ref
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_yaml(root, ref)
          msg = resolved
        else
          return
        end
      end
      if msg.as_h? && (payload_node = msg[YAML::Any.new("payload")]?)
        collect_schema_props_yaml(root, payload_node, "json", params)
      end
    end

    private def collect_schema_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # A scalar schema (e.g. JSON-Schema boolean, or an allOf element `true`)
      # makes the `[...]?` subscripts below raise "Expected Hash".
      return unless schema.as_h?
      if ref_node = schema[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return if seen.includes?(ref)
          seen << ref
          if resolved = resolve_ref_yaml(root, ref)
            collect_schema_props_yaml(root, resolved, param_type, params, seen)
          end
        end
        return
      end

      if props_node = schema[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            params << Param.new(name.to_s, "", param_type)
          end
        end
      end

      if all_of_node = schema[YAML::Any.new("allOf")]?
        if all_of = all_of_node.as_a?
          all_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
        end
      end
    end

    private def resolve_ref_yaml(root : YAML::Any, ref : String) : YAML::Any?
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

    # --- shared ---------------------------------------------------------

    private def push_endpoint(channel : String, method : String, params : Array(Param), protocol : String?, details : Details)
      endpoint = if params.empty?
                   Endpoint.new(channel, method, details)
                 else
                   Endpoint.new(channel, method, params, details)
                 end
      endpoint.protocol = protocol if protocol && !protocol.empty?
      @result << endpoint
    end
  end
end
