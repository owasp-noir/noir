require "../../../models/analyzer"

module Analyzer::Specification
  class AzureFunctions < Analyzer
    METHOD_ANY = "ANY"

    def analyze
      spec_files = CodeLocator.instance.all("azure-functions-spec")
      return @result unless spec_files.is_a?(Array(String))

      spec_files.each do |path|
        next unless File.exists?(path)

        details = Details.new(PathInfo.new(path))
        content = read_file_content(path)
        begin
          process_doc(JSON.parse(content), path, details)
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_doc(doc : JSON::Any, path : String, details : Details)
      bindings = doc["bindings"]?.try(&.as_a?)
      return unless bindings

      function_name = File.basename(File.dirname(path))

      bindings.each do |binding|
        binding_h = binding.as_h?
        next unless binding_h

        type = binding_h["type"]?.try(&.as_s?) || ""
        next unless type == "httpTrigger"

        methods = extract_methods(binding_h["methods"]?)
        methods = [METHOD_ANY] if methods.empty?

        route = binding_h["route"]?.try(&.as_s?) || function_name
        normalized_path = route.starts_with?('/') ? route : "/#{route}"

        auth_level = binding_h["authLevel"]?.try(&.as_s?)

        methods.each do |method|
          endpoint = Endpoint.new(normalized_path, method, details)
          endpoint.add_tag(Tag.new("azure-function-name", function_name, "azure_functions_analyzer"))
          endpoint.add_tag(Tag.new("azure-auth-level", auth_level, "azure_functions_analyzer")) if auth_level && !auth_level.empty?
          @result << endpoint
        end
      end
    end

    private def extract_methods(node : JSON::Any?) : Array(String)
      return [] of String if node.nil?
      arr = node.as_a?
      return [] of String unless arr
      arr.compact_map(&.as_s?).reject(&.empty?).map(&.upcase)
    end
  end
end
