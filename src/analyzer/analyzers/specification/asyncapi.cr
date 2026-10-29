require "../../engines/specification_engine"

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
  class AsyncApi < SpecificationEngine
    analyzer_for "asyncapi"

    # Operation keys on `channels` entries (2.x).
    OPERATIONS_2X = {"publish", "subscribe"}

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::ASYNCAPI_JSON) do |path, details|
        content = read_file_content(path)
        process_json(parse_json_lenient(content), details, path)
      end

      each_spec_file_with_details(Noir::LocatorKeys::ASYNCAPI_YAML) do |path, details|
        content = read_file_content(path)
        process_yaml(YAML.parse(content), details, path)
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

        channel_ref = op_h["channel"]?
        channel_path = resolve_channel_path_json(root, channel_ref, channels)
        next if channel_path.empty?

        params = [] of Param
        channel = resolved_channel_json(root, channel_ref)
        collect_v3_messages_json(root, op_h, channel, params)
        collect_ws_query_json(root, channel, params)

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

    # AsyncAPI 3: omitted `operation.messages` means every message on the
    # channel. A present key, even an empty list, is an explicit selection.
    private def collect_v3_messages_json(root : JSON::Any, op_h : Hash(String, JSON::Any), channel : JSON::Any?, params : Array(Param))
      if messages_node = op_h["messages"]?
        collect_message_list_json(root, messages_node, params)
        return
      end
      return unless channel
      if messages_node = channel["messages"]?
        collect_message_list_json(root, messages_node, params)
      end
    end

    private def collect_message_list_json(root : JSON::Any, messages_node : JSON::Any, params : Array(Param))
      if messages = messages_node.as_a?
        messages.each { |m| collect_message_payload_json(root, m, params) }
      elsif messages = messages_node.as_h?
        messages.each_value { |m| collect_message_payload_json(root, m, params) }
      end
    end

    private def resolved_channel_json(root : JSON::Any, channel_ref : JSON::Any?) : JSON::Any?
      return unless channel_ref && channel_ref.as_h?
      if ref = channel_ref["$ref"]?.try(&.as_s?)
        return resolve_ref_json(root, ref)
      end
      channel_ref
    end

    private def collect_ws_query_json(root : JSON::Any, channel : JSON::Any?, params : Array(Param))
      return unless channel
      query = channel["bindings"]?.try(&.as_h?)
        .try(&.["ws"]?).try(&.as_h?)
        .try(&.["query"]?)
      return unless query
      collect_schema_props_json(root, query, "query", params)
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
      # AsyncAPI 2.x lets one operation carry several messages:
      # `message: {oneOf: [...]}`.
      if one_of = msg.as_h?.try(&.["oneOf"]?).try(&.as_a?)
        one_of.each { |m| collect_message_payload_json(root, m, params, seen) }
      elsif msg.as_h? && (payload = msg["payload"]?)
        collect_schema_props_json(root, payload, "json", params)
      end
    end

    private def collect_schema_props_json(root : JSON::Any, schema : JSON::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # A scalar schema (e.g. JSON-Schema boolean, or an allOf element `true`)
      # makes the `["..."]?` subscripts below raise "Expected Hash".
      # `schemaFormat` marks a Multi Format Schema Object: the schema itself
      # lives under `schema`, not beside the format string. A payload that
      # already has `properties` at the top has no `schemaFormat` and stays.
      node = schema_node_json(schema)
      return unless node.as_h?
      if ref = node["$ref"]?.try(&.as_s?)
        return if seen.includes?(ref)
        seen << ref
        if resolved = resolve_ref_json(root, ref)
          collect_schema_props_json(root, resolved, param_type, params, seen)
        end
        return
      end

      if props = node["properties"]?.try(&.as_h?)
        props.each do |name, _|
          add_param(params, name.to_s, param_type)
        end
      end

      if all_of = node["allOf"]?.try(&.as_a?)
        all_of.each { |s| collect_schema_props_json(root, s, param_type, params, seen) }
      end
    end

    private def schema_node_json(schema : JSON::Any) : JSON::Any
      return schema unless hash = schema.as_h?
      return schema unless hash["schemaFormat"]?
      hash["schema"]? || schema
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
        channel = resolved_channel_yaml(root, channel_ref)
        collect_v3_messages_yaml(root, op_h, channel, params)
        collect_ws_query_yaml(root, channel, params)

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

    private def collect_v3_messages_yaml(root : YAML::Any, op_h : Hash(YAML::Any, YAML::Any), channel : YAML::Any?, params : Array(Param))
      if messages_node = op_h[YAML::Any.new("messages")]?
        collect_message_list_yaml(root, messages_node, params)
        return
      end
      return unless channel
      if messages_node = channel[YAML::Any.new("messages")]?
        collect_message_list_yaml(root, messages_node, params)
      end
    end

    private def collect_message_list_yaml(root : YAML::Any, messages_node : YAML::Any, params : Array(Param))
      if messages = messages_node.as_a?
        messages.each { |m| collect_message_payload_yaml(root, m, params) }
      elsif messages = messages_node.as_h?
        messages.each_value { |m| collect_message_payload_yaml(root, m, params) }
      end
    end

    private def resolved_channel_yaml(root : YAML::Any, channel_ref : YAML::Any?) : YAML::Any?
      return unless channel_ref && channel_ref.as_h?
      if ref = channel_ref[YAML::Any.new("$ref")]?.try(&.as_s?)
        return resolve_ref_yaml(root, ref)
      end
      channel_ref
    end

    private def collect_ws_query_yaml(root : YAML::Any, channel : YAML::Any?, params : Array(Param))
      return unless channel
      bindings = channel[YAML::Any.new("bindings")]?.try(&.as_h?)
      return unless bindings
      ws = bindings[YAML::Any.new("ws")]?.try(&.as_h?)
      return unless ws
      query = ws[YAML::Any.new("query")]?
      return unless query
      collect_schema_props_yaml(root, query, "query", params)
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
      # AsyncAPI 2.x lets one operation carry several messages:
      # `message: {oneOf: [...]}`.
      if one_of = msg.as_h?.try(&.[YAML::Any.new("oneOf")]?).try(&.as_a?)
        one_of.each { |m| collect_message_payload_yaml(root, m, params, seen) }
      elsif msg.as_h? && (payload_node = msg[YAML::Any.new("payload")]?)
        collect_schema_props_yaml(root, payload_node, "json", params)
      end
    end

    private def collect_schema_props_yaml(root : YAML::Any, schema : YAML::Any, param_type : String, params : Array(Param), seen : Set(String) = Set(String).new)
      # A scalar schema (e.g. JSON-Schema boolean, or an allOf element `true`)
      # makes the `[...]?` subscripts below raise "Expected Hash".
      # `schemaFormat` marks a Multi Format Schema Object: the schema itself
      # lives under `schema`, not beside the format string. A payload that
      # already has `properties` at the top has no `schemaFormat` and stays.
      node = schema_node_yaml(schema)
      return unless node.as_h?
      if ref_node = node[YAML::Any.new("$ref")]?
        if ref = ref_node.as_s?
          return if seen.includes?(ref)
          seen << ref
          if resolved = resolve_ref_yaml(root, ref)
            collect_schema_props_yaml(root, resolved, param_type, params, seen)
          end
        end
        return
      end

      if props_node = node[YAML::Any.new("properties")]?
        if props = props_node.as_h?
          props.each do |name, _|
            add_param(params, name.to_s, param_type)
          end
        end
      end

      if all_of_node = node[YAML::Any.new("allOf")]?
        if all_of = all_of_node.as_a?
          all_of.each { |s| collect_schema_props_yaml(root, s, param_type, params, seen) }
        end
      end
    end

    private def schema_node_yaml(schema : YAML::Any) : YAML::Any
      return schema unless hash = schema.as_h?
      return schema unless hash[YAML::Any.new("schemaFormat")]?
      hash[YAML::Any.new("schema")]? || schema
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
