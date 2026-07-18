require "../../../models/analyzer"
require "uri"

module Analyzer::Specification
  # OpenRPC 1.x analyzer.
  #
  # JSON-RPC exposes a single HTTP path and selects the operation via the
  # `"method"` field in the request body, so `methods[]` cannot map onto
  # distinct URLs on its own. We emit **one endpoint per RPC method**,
  # disambiguated by a URL fragment:
  #
  #     POST /rpc#eth_getBalance
  #
  # This mirrors `GraphqlSdlParser`'s `/graphql#Query.user` convention. The
  # fragment is load-bearing: the optimizer dedupes on `(method, url, scope)`,
  # so without it every RPC method would collapse into one merged endpoint.
  #
  # Each endpoint also carries a `jsonrpc_<method>` body param whose value is a
  # ready-to-send JSON-RPC 2.0 request envelope, the same way the GraphQL
  # analyzers attach a `graphql_<operation>_<field>` document param.
  class OpenRpc < Analyzer
    # Fallback when the document declares no usable server URL. JSON-RPC has
    # no canonical path the way GraphQL has `/graphql`, so stay at the root
    # rather than inventing one.
    DEFAULT_RPC_PATH = "/"

    def analyze
      locator = CodeLocator.instance
      jsons = locator.all("openrpc-json")
      return @result unless jsons.is_a?(Array(String))

      jsons.each do |path|
        next unless File.exists?(path)
        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        process_document(JSON.parse(content), details)
      rescue e
        @logger.debug "Exception parsing OpenRPC #{path}"
        @logger.debug_sub e
      end

      @result
    end

    private def process_document(root : JSON::Any, details : Details)
      base_path = base_path_for(root)
      return unless methods = root["methods"]?.try(&.as_a?)

      methods.each do |method_entry|
        resolved = resolve_node(root, method_entry)
        next unless method_obj = resolved.try(&.as_h?)

        name = method_obj["name"]?.try(&.as_s?) || ""
        next if name.empty?

        descriptors = param_descriptors(root, method_obj)
        param_structure = method_obj["paramStructure"]?.try(&.as_s?)

        params = [] of Param
        descriptors.each { |descriptor| push_param(params, Param.new(descriptor, "", "json")) }
        push_param(params, Param.new(
          "jsonrpc_#{name}",
          request_envelope(name, descriptors, param_structure),
          "json"
        ))

        endpoint = Endpoint.new("#{base_path}##{name}", "POST", params, details)
        endpoint.add_tag(Tag.new("jsonrpc", name, "openrpc_analyzer"))
        if structure = param_structure
          endpoint.add_tag(Tag.new("jsonrpc-param-structure", structure, "openrpc_analyzer"))
        end
        if result_name = result_name_for(root, method_obj)
          endpoint.add_tag(Tag.new("jsonrpc-return", result_name, "openrpc_analyzer"))
        end

        @result << endpoint
      end
    end

    # `params[]` holds ContentDescriptor objects, each of which may itself be a
    # `$ref` into `components.contentDescriptors`. Only the descriptor *names*
    # become params: those are the named arguments on the wire. Flattening the
    # nested schema properties would misrepresent the request shape.
    private def param_descriptors(root : JSON::Any, method_obj : Hash(String, JSON::Any)) : Array(String)
      names = [] of String
      return names unless params = method_obj["params"]?.try(&.as_a?)

      params.each do |param_entry|
        resolved = resolve_node(root, param_entry)
        next unless descriptor = resolved.try(&.as_h?)
        name = descriptor["name"]?.try(&.as_s?) || ""
        names << name unless name.empty? || names.includes?(name)
      end

      names
    end

    private def result_name_for(root : JSON::Any, method_obj : Hash(String, JSON::Any)) : String?
      return unless result_entry = method_obj["result"]?
      resolved = resolve_node(root, result_entry)
      return unless result_obj = resolved.try(&.as_h?)
      name = result_obj["name"]?.try(&.as_s?)
      return if name.nil? || name.empty?
      name
    end

    # A replayable JSON-RPC 2.0 request. `paramStructure` decides whether the
    # `params` member is by-name (object) or by-position (array); the spec's
    # default when the key is absent is "either", which we render positionally.
    private def request_envelope(name : String, descriptors : Array(String), param_structure : String?) : String
      params_node = if param_structure == "by-name"
                      JSON::Any.new(descriptors.to_h { |descriptor| {descriptor, JSON::Any.new("")} })
                    else
                      JSON::Any.new(descriptors.map { |_| JSON::Any.new("") })
                    end

      {
        "jsonrpc" => JSON::Any.new("2.0"),
        "method"  => JSON::Any.new(name),
        "params"  => params_node,
        "id"      => JSON::Any.new(1_i64),
      }.to_json
    end

    private def push_param(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    # Mirrors the OAS3 analyzer's server handling so `--url` behaves the same
    # across spec families: an absolute server URL only contributes its path
    # when its host matches the user-supplied URL.
    private def base_path_for(root : JSON::Any) : String
      servers = root["servers"]?.try(&.as_a?)
      if servers
        servers.each do |server_obj|
          server_url = server_obj["url"]?.try(&.as_s?) || ""
          next if server_url.empty?

          if server_url.starts_with?("http")
            next if @url.empty?
            user_uri = URI.parse(@url)
            source_uri = URI.parse(server_url)
            return combine_base_url(source_uri.path) if user_uri.host == source_uri.host
          elsif server_url.starts_with?("/")
            return combine_base_url(server_url)
          else
            return combine_base_url("/#{server_url}")
          end
        rescue
          next
        end
      end

      @url.empty? ? DEFAULT_RPC_PATH : @url
    end

    private def combine_base_url(path : String) : String
      return @url if path.empty?
      return path if @url.empty?
      if @url.ends_with?("/") && path.starts_with?("/")
        @url + path[1..]
      elsif !@url.ends_with?("/") && !path.starts_with?("/")
        "#{@url}/#{path}"
      else
        @url + path
      end
    end

    # Follows a `$ref` chain to its target, guarding against cycles. Returns the
    # node itself when it isn't a reference.
    private def resolve_node(root : JSON::Any, node : JSON::Any) : JSON::Any?
      current = node
      seen = Set(String).new

      while current.as_h? && (ref = current["$ref"]?.try(&.as_s?))
        return if seen.includes?(ref)
        seen << ref
        resolved = resolve_ref(root, ref)
        return unless resolved
        current = resolved
      end

      current
    end

    private def resolve_ref(root : JSON::Any, ref : String) : JSON::Any?
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
  end
end
