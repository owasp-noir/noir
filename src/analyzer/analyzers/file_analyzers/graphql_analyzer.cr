require "../../../models/analyzer"
require "../../../models/endpoint"
require "json"
require "regex" # Explicitly require Regex

# Define the regex as a top-level constant in this file
OPERATION_REGEX = Regex.new("(query|mutation|subscription)\\s+([_A-Za-z][_0-9A-Za-z]*)")

module InternalGraphqlParser
  def self.parse_content(path : String, file_content : String) : Array(Endpoint)
    results = [] of Endpoint

    file_content.each_line.with_index do |line, index|
      current_offset = 0
      while match_data = OPERATION_REGEX.match(line, current_offset)
        operation_type_capture = match_data.captures[0]?
        operation_name_capture = match_data.captures[1]?

        if operation_type_capture && operation_name_capture
          operation_type = operation_type_capture
          operation_name = operation_name_capture

          endpoint_url = "/graphql"
          endpoint_method = "POST"
          param_value_hash = {operation_type => operation_name}
          param_value_json = param_value_hash.to_json
          param_name = "graphql_operation_#{operation_type}_#{operation_name}"

          param = Param.new(param_name, param_value_json, "json")
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint = Endpoint.new(endpoint_url, endpoint_method, details)
          endpoint.push_param(param)
          results << endpoint
        end

        full_match_string = match_data[0]?
        if full_match_string
          found_at_index = line.index(full_match_string, current_offset)
          if found_at_index
            match_length = full_match_string.bytesize
            current_offset = found_at_index + match_length
            if match_length == 0
              current_offset = found_at_index + 1
            end
          else
            current_offset += 1 # Fallback
          end
        else
          current_offset += 1 # Fallback
        end
        break if current_offset >= line.bytesize
      end
    end
    results
  end
end

FileAnalyzer.add_hook(->(path : String, _url : String) : Array(Endpoint) {
  # Only process .graphql files
  return [] of Endpoint unless path.ends_with?(".graphql")

  file_content = ""
  begin
    file_content = File.read(path, encoding: "utf-8", invalid: :skip)
  rescue ex
    STDERR.puts "GraphQL Analyzer: Error reading file #{path}: #{ex.message} (#{ex.class})"
    return [] of Endpoint # Return empty if read fails
  end

  InternalGraphqlParser.parse_content(path, file_content)
})
