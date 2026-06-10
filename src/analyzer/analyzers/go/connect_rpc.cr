require "../../../models/analyzer"
require "../../engines/go_engine"

module Analyzer::Go
  # Connect (https://connectrpc.com/) is Buf's gRPC-compatible RPC
  # framework. Generated handlers expose each service method as
  # `POST /<package>.<Service>/<Method>` over plain HTTP, with JSON
  # and proto content-types negotiated through `Content-Type`. The
  # service surface is identical to gRPC's, so we reuse the proto
  # files already registered by the gRPC detector.
  #
  # The analyzer is proto-driven by default — every `rpc` method on
  # every service in a `.proto` file becomes one Connect endpoint —
  # and uses a `NewXxxServiceHandler(` scan over Go sources to attach
  # the wired-up service's mount path when available. A code-driven
  # mount discovery is run alongside so endpoints reference the Go
  # file that registers the handler instead of (or in addition to)
  # the proto file.
  class ConnectRpc < GoEngine
    IMPORT_MARKER         = "connectrpc.com/connect"
    HANDLER_NAME_REGEX    = /New(\w+ServiceHandler)\s*\(/
    CONNECT_CONTENT_TYPES = "application/proto, application/json, application/connect+proto, application/connect+json"

    alias MessageFields = Array(Param)
    alias ServiceMountKey = Tuple(String, String)
    alias ServiceMount = NamedTuple(file: String, line: Int32)

    # Maps the generated handler-constructor to a streaming descriptor.
    HANDLER_KIND_REGEX = /connect\.New(Unary|ClientStream|ServerStream|BidiStream)Handler\s*\(\s*(\w+Procedure)/m
    PROCEDURE_REGEX    = /\b(\w+Procedure)\s*=\s*"(\/[\w.]+\/\w+)"/

    def analyze
      locator = CodeLocator.instance
      proto_files = locator.all("grpc-proto")

      unless proto_files.empty?
        service_mounts = discover_service_mounts

        proto_files.each do |proto_file|
          begin
            content = read_file_content(proto_file)
            parse_proto(content, proto_file, service_mounts)
          rescue File::NotFoundError
            @logger.debug "Proto file not found during analysis, skipping: #{proto_file}"
          rescue e
            @logger.debug "ConnectRpc parse error for #{proto_file}: #{e.message}"
          end
        end
      end

      # Fallback/supplement: generated `*.connect.go` files declare every
      # RPC's fully-qualified route as a `XxxProcedure = "/pkg.Service/
      # Method"` constant. Repos that ship only the generated code (no
      # committed `.proto`) would otherwise produce zero endpoints. URLs
      # already surfaced from a proto are skipped so the richer
      # proto-driven endpoints (params/streaming) win when both exist.
      seen_urls = Set(String).new
      @result.each { |ep| seen_urls << ep.url }
      discover_connect_go_endpoints(seen_urls)

      @result
    end

    # Scans generated `*.connect.go` files for RPC procedure constants and
    # emits one Connect endpoint per fully-qualified route not already
    # covered by a proto. Streaming is recovered from the matching
    # `connect.NewXxxHandler(XxxProcedure, ...)` constructor.
    private def discover_connect_go_endpoints(seen_urls : Set(String))
      get_files_by_extension(".go").each do |path|
        next if File.directory?(path)
        next if GoEngine.go_test_file?(path)
        begin
          content = read_file_content(path)
          next unless content.includes?(IMPORT_MARKER)
          next unless content.includes?("Procedure")

          kinds = {} of String => String
          content.scan(HANDLER_KIND_REGEX) do |m|
            kinds[m[2]] = m[1]
          end

          content.each_line.with_index do |line, index|
            if m = line.match(PROCEDURE_REGEX)
              const_name = m[1]
              url = m[2]
              next if seen_urls.includes?(url)
              seen_urls << url

              details = Details.new(PathInfo.new(path, index + 1))
              endpoint = Endpoint.new(url, "POST", details)
              endpoint.protocol = "connect"
              endpoint.add_tag(Tag.new("content-type", CONNECT_CONTENT_TYPES, "connect_rpc_analyzer"))

              if kind = kinds[const_name]?
                streaming_desc = case kind
                                 when "ClientStream" then "client-streaming"
                                 when "ServerStream" then "server-streaming"
                                 when "BidiStream"   then "client-streaming, server-streaming"
                                 end
                endpoint.add_tag(Tag.new("streaming", streaming_desc, "connect_rpc_analyzer")) if streaming_desc
              end

              @result << endpoint
            end
          end
        rescue File::NotFoundError
          @logger.debug "connect.go not found during analysis, skipping: #{path}"
        rescue e
          @logger.debug "ConnectRpc connect.go parse error for #{path}: #{e.message}"
        end
      end
    end

    # Walks every `.go` file in the project once, records each
    # `NewXxxServiceHandler(` registration, and returns a map from
    # the proto service base name (`UserService`) to the first
    # `(file, line)` registration found. Used downstream to attach a
    # code path to the Go mount point in addition to the proto file.
    private def discover_service_mounts : Hash(ServiceMountKey, ServiceMount)
      mounts = {} of ServiceMountKey => ServiceMount
      begin
        get_files_by_extension(".go").each do |path|
          next if File.directory?(path)
          next if GoEngine.go_test_file?(path)
          base_path = configured_base_for(path)
          content = read_file_content(path)
          next unless content.includes?(IMPORT_MARKER) || content.includes?("ServiceHandler(")
          content.each_line.with_index do |line, index|
            if match = line.match(HANDLER_NAME_REGEX)
              handler_name = match[1]
              # Strip the trailing "Handler" -> service base name
              service_name = handler_name.sub(/Handler$/, "")
              mounts[{base_path, service_name}] ||= {file: path, line: index + 1}
            end
          end
        end
      rescue e
        @logger.debug "ConnectRpc mount discovery error: #{e.message}"
      end
      mounts
    end

    private def parse_proto(content : String, file_path : String, mounts : Hash(ServiceMountKey, ServiceMount))
      package = parse_package(content)
      messages = parse_messages(content)
      parse_services(content, file_path, package, messages, mounts)
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

      content.scan(/message\s+(\w+)\s*\{/m) do |match|
        msg_name = match[1]
        start_pos = match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        msg_body = extract_brace_block(content, brace_pos)
        next if msg_body.nil?

        fields = [] of Param

        msg_body.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("//") || line.starts_with?("reserved") || line.starts_with?("option")
          next if line.starts_with?("message ") || line.starts_with?("enum ") || line.starts_with?("oneof ")
          next if line == "}"

          if field_match = line.match(/^\s*(?:optional\s+|repeated\s+|required\s+)?(?:map<[\w.]+\s*,\s*[\w.]+>|[\w.]+)\s+(\w+)\s*=\s*\d+/)
            fields << Param.new(field_match[1], "", "json")
          end
        end

        messages[msg_name] = fields
      end

      messages
    end

    private def parse_services(content : String, file_path : String, package : String, messages : Hash(String, MessageFields), mounts : Hash(ServiceMountKey, ServiceMount))
      content.scan(/service\s+(\w+)\s*\{/m) do |service_match|
        service_name = service_match[1]
        start_pos = service_match.begin(0) || 0
        brace_pos = content.index('{', start_pos)
        next if brace_pos.nil?
        service_body = extract_brace_block(content, brace_pos)
        next if service_body.nil?

        parse_rpc_methods(service_body, file_path, package, service_name, messages, content, mounts)
      end
    end

    private def extract_brace_block(content : String, open_pos : Int32) : String?
      depth = 0
      pos = open_pos
      in_string = false
      while pos < content.size
        ch = content[pos]
        if in_string
          # A quote closes the string only when preceded by an EVEN number of
          # backslashes (so `\\"` = literal backslash + terminator toggles, but
          # `\"` = escaped quote does not).
          if ch == '"'
            bs = 0
            bp = pos - 1
            while bp >= 0 && content[bp] == '\\'
              bs += 1
              bp -= 1
            end
            in_string = false if bs.even?
          end
        elsif ch == '/' && pos + 1 < content.size && content[pos + 1] == '/'
          # Line comment: skip to EOL so a stray `}` or `"` can't shift state.
          nl = content.index('\n', pos)
          pos = nl.nil? ? content.size : nl
          next
        elsif ch == '/' && pos + 1 < content.size && content[pos + 1] == '*'
          # Block comment: skip to the closing */.
          close = content.index("*/", pos + 2)
          pos = close.nil? ? content.size : close + 2
          next
        elsif ch == '"'
          in_string = true
        elsif ch == '{'
          depth += 1
        elsif ch == '}'
          depth -= 1
          return content[(open_pos + 1)..(pos - 1)] if depth == 0
        end
        pos += 1
      end
      nil
    end

    private def parse_rpc_methods(service_body : String, file_path : String, package : String, service_name : String, messages : Hash(String, MessageFields), full_content : String, mounts : Hash(ServiceMountKey, ServiceMount))
      mount = mounts[{configured_base_for(file_path), service_name}]?

      service_body.scan(/rpc\s+(\w+)\s*\(\s*(stream\s+)?(\.?\w+(?:\.\w+)*)\s*\)\s*returns\s*\(\s*(stream\s+)?(\.?\w+(?:\.\w+)*)\s*\)/m) do |rpc_match|
        method_name = rpc_match[1]
        request_streaming = !rpc_match[2]?.nil?
        request_type = rpc_match[3]
        response_streaming = !rpc_match[4]?.nil?

        line_number = find_line_number(full_content, method_name)

        # Prefer the Go handler mount as the primary code path when we
        # found one; the proto file is the spec, the Go file is the
        # actual wire-up.
        details = if mount
                    Details.new(PathInfo.new(mount[:file], mount[:line]))
                  else
                    Details.new(PathInfo.new(file_path, line_number))
                  end

        params = [] of Param
        if msg_fields = messages[request_type]?
          params = msg_fields.dup
        end

        url = if package.empty?
                "/#{service_name}/#{method_name}"
              else
                "/#{package}.#{service_name}/#{method_name}"
              end

        endpoint = Endpoint.new(url, "POST", params, details)
        endpoint.protocol = "connect"
        endpoint.add_tag(Tag.new("content-type", CONNECT_CONTENT_TYPES, "connect_rpc_analyzer"))

        if request_streaming || response_streaming
          streaming_desc = String.build do |s|
            s << "client-streaming" if request_streaming
            s << ", " if request_streaming && response_streaming
            s << "server-streaming" if response_streaming
          end
          endpoint.add_tag(Tag.new("streaming", streaming_desc, "connect_rpc_analyzer"))
        end

        @result << endpoint
      end
    end

    private def find_line_number(content : String, method_name : String) : Int32?
      # Hoisted out of the loop: an interpolated regex literal recompiles
      # (PCRE2 JIT) on every evaluation, i.e. once per line.
      rpc_regex = /\brpc\s+#{Regex.escape(method_name)}\s*\(/
      content.each_line.with_index do |line, index|
        next unless line.includes?(method_name)
        if line =~ rpc_regex
          return index + 1
        end
      end
      nil
    end
  end
end
