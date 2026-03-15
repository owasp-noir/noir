require "../../../models/analyzer"

module Analyzer::Specification
  class Grpc < Analyzer
    # Represents a parsed protobuf message with its fields
    alias MessageFields = Array(Param)

    def analyze
      locator = CodeLocator.instance
      proto_files = locator.all("grpc-proto")

      if proto_files.is_a?(Array(String))
        proto_files.each do |proto_file|
          next unless File.exists?(proto_file)
          content = File.read(proto_file, encoding: "utf-8", invalid: :skip)
          parse_proto(content, proto_file)
        end
      end

      @result
    end

    private def parse_proto(content : String, file_path : String)
      package = parse_package(content)
      messages = parse_messages(content)
      parse_services(content, file_path, package, messages)
    end

    private def parse_package(content : String) : String
      if match = content.match(/^\s*package\s+([\w.]+)\s*;/m)
        match[1]
      else
        ""
      end
    end

    private def parse_messages(content : String) : Hash(String, MessageFields)
      messages = {} of String => MessageFields

      # Match message blocks (non-nested for simplicity)
      content.scan(/message\s+(\w+)\s*\{([^}]*)\}/m) do |match|
        msg_name = match[1]
        msg_body = match[2]
        fields = [] of Param

        msg_body.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("//") || line.starts_with?("reserved") || line.starts_with?("option")

          # Match field patterns: [optional|repeated] type name = number;
          if field_match = line.match(/^\s*(?:optional\s+|repeated\s+|required\s+)?(?:map<[\w.]+\s*,\s*[\w.]+>|[\w.]+)\s+(\w+)\s*=\s*\d+/)
            fields << Param.new(field_match[1], "", "json")
          end
        end

        messages[msg_name] = fields
      end

      messages
    end

    private def parse_services(content : String, file_path : String, package : String, messages : Hash(String, MessageFields))
      # Find service blocks using brace matching
      content.scan(/service\s+(\w+)\s*\{/m) do |service_match|
        service_name = service_match[1]
        # Find the opening brace position and extract balanced block
        start_pos = service_match.begin(0).not_nil!
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        service_body = extract_brace_block(content, brace_pos)
        next if service_body.nil?

        parse_rpc_methods(service_body, file_path, package, service_name, messages, content)
      end
    end

    private def extract_brace_block(content : String, open_pos : Int32) : String?
      depth = 0
      pos = open_pos
      while pos < content.size
        case content[pos]
        when '{'
          depth += 1
        when '}'
          depth -= 1
          if depth == 0
            return content[(open_pos + 1)..(pos - 1)]
          end
        end
        pos += 1
      end
      nil
    end

    private def parse_rpc_methods(service_body : String, file_path : String, package : String, service_name : String, messages : Hash(String, MessageFields), full_content : String)
      # Find each rpc definition and its associated options block
      service_body.scan(/rpc\s+(\w+)\s*\(\s*(stream\s+)?(\w+)\s*\)\s*returns\s*\(\s*(stream\s+)?(\w+)\s*\)/m) do |rpc_match|
        method_name = rpc_match[1]
        request_type = rpc_match[3]
        response_type = rpc_match[5]

        # Find the options block after the rpc signature
        rpc_end = rpc_match.end(0).not_nil!
        remaining = service_body[rpc_end..]
        options_block = ""
        if remaining =~ /\A\s*\{/
          brace_pos = service_body.index('{', rpc_end)
          if brace_pos
            block = extract_brace_block(service_body, brace_pos)
            options_block = block || ""
          end
        end

        # Find line number
        line_number = find_line_number(full_content, method_name)
        details = Details.new(PathInfo.new(file_path, line_number))

        # Extract params from request message
        params = [] of Param
        if msg_fields = messages[request_type]?
          params = msg_fields.dup
        end

        # Check for gRPC-Gateway annotations
        http_mappings = parse_http_annotations(options_block)

        if http_mappings.empty?
          # Pure gRPC endpoint
          url = "/#{package}.#{service_name}/#{method_name}"
          endpoint = Endpoint.new(url, "POST", params, details)
          endpoint.protocol = "grpc"
          @result << endpoint
        else
          # gRPC-Gateway: create HTTP endpoint(s)
          http_mappings.each do |mapping|
            http_method = mapping[:method]
            http_path = mapping[:path]

            # Extract path parameters
            gateway_params = [] of Param
            http_path.scan(/\{(\w+(?:\.\w+)*)\}/) do |path_match|
              gateway_params << Param.new(path_match[1], "", "path")
            end

            # Add body params from message fields (unless body is "*" meaning all, or specific field)
            body_field = mapping[:body]?
            if body_field == "*"
              # All message fields go to body
              params.each do |p|
                # Skip fields already in path
                next if gateway_params.any? { |gp| gp.name == p.name }
                gateway_params << p
              end
            elsif body_field && !body_field.empty?
              # Specific field is the body
              gateway_params << Param.new(body_field, "", "json")
            else
              # No body specified - remaining fields become query params for GET/DELETE
              if http_method == "GET" || http_method == "DELETE"
                params.each do |p|
                  next if gateway_params.any? { |gp| gp.name == p.name }
                  gateway_params << Param.new(p.name, "", "query")
                end
              else
                params.each do |p|
                  next if gateway_params.any? { |gp| gp.name == p.name }
                  gateway_params << p
                end
              end
            end

            endpoint = Endpoint.new(http_path, http_method, gateway_params, details)
            @result << endpoint
          end
        end
      end
    end

    private def parse_http_annotations(options_block : String) : Array(NamedTuple(method: String, path: String, body: String?))
      mappings = [] of NamedTuple(method: String, path: String, body: String?)

      # Match google.api.http option
      return mappings unless options_block.includes?("google.api.http")

      body_value : String? = nil
      if body_match = options_block.match(/body\s*:\s*"([^"]*)"/)
        body_value = body_match[1]
      end

      # Match HTTP method patterns
      {% for http_method in ["get", "post", "put", "delete", "patch"] %}
        if match = options_block.match(/{{ http_method.id }}\s*:\s*"([^"]*)"/)
          mappings << {method: {{ http_method.upcase }}, path: match[1], body: body_value}
        end
      {% end %}

      # Match additional_bindings
      if options_block.includes?("additional_bindings")
        options_block.scan(/additional_bindings\s*\{([^}]*)\}/) do |binding_match|
          binding_body = binding_match[1]
          binding_body_value : String? = nil
          if bb_match = binding_body.match(/body\s*:\s*"([^"]*)"/)
            binding_body_value = bb_match[1]
          end

          {% for http_method in ["get", "post", "put", "delete", "patch"] %}
            if match = binding_body.match(/{{ http_method.id }}\s*:\s*"([^"]*)"/)
              mappings << {method: {{ http_method.upcase }}, path: match[1], body: binding_body_value}
            end
          {% end %}
        end
      end

      mappings
    end

    private def find_line_number(content : String, method_name : String) : Int32?
      content.each_line.with_index do |line, index|
        if line.includes?("rpc") && line.includes?(method_name)
          return index + 1
        end
      end
      nil
    end
  end
end
