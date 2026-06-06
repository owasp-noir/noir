require "base64"
require "../../../models/analyzer"
require "../../../models/endpoint"
require "json"

def parse_params(query : String?, params : Array(Param), type : String)
  return unless query
  query.to_s.split("&").each do |param|
    next if param.empty?
    pair = param.split("=", 2)
    params << Param.new(pair[0], pair[1]? || "", type)
  end
end

def parse_body(body : String, params : Array(Param))
  return if body.empty?
  begin
    json_body = JSON.parse(body)
    json_body.as_h.each do |key, value|
      params << Param.new(key, value.to_s, "json")
    end
  rescue
    # Not valid JSON: treat as a urlencoded form body. Skip fragments that
    # have no `=` (e.g. an incomplete JSON accumulation) instead of crashing
    # on the multiple-assignment.
    body.split("&").each do |param|
      pair = param.split("=", 2)
      next if pair.size < 2
      params << Param.new(pair[0], pair[1], "form")
    end
  end
end

FileAnalyzer.add_hook(->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint

  return results unless File.extname(path) == ".http"

  begin
    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
      method = ""
      endpoint_url = ""
      headers = false
      body = ""
      params = [] of Param
      parsed_url = URI.parse("")
      start_line = 0

      # Commit the request accumulated so far (if any) as one endpoint. The
      # body is parsed once here on the fully-accumulated text, and params is
      # dup'd so the emitted endpoint can never be mutated by a later request.
      commit = -> {
        if !endpoint_url.empty? && parsed_url.to_s.includes?(url)
          parse_body(body, params)
          details = Details.new(PathInfo.new(path, start_line))
          results << Endpoint.new(parsed_url.path, method, params.dup, details)
        end
      }

      reset = -> {
        method = ""
        endpoint_url = ""
        headers = false
        body = ""
        params = [] of Param
        parsed_url = URI.parse("")
      }

      file.each_line.with_index do |line, index|
        stripped = line.strip

        # `###` (optionally followed by a label) separates requests.
        if stripped.starts_with?("###")
          commit.call
          reset.call
          next
        end

        # Skip true comments (the `###` separator is handled above).
        next if line.starts_with?("#") || line.starts_with?("//")

        if line.match(/^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD) (https?:\/\/[^\s]+)/)
          # A new request line ends the previous one even without a `###`.
          commit.call
          reset.call

          method, endpoint_url = line.split
          headers = true
          parsed_url = URI.parse(endpoint_url)
          start_line = index + 1
          parse_params(parsed_url.query, params, "query")
        elsif headers && stripped.empty?
          headers = false
        elsif headers
          header_parts = line.split(": ", 2)
          params << Param.new(header_parts[0], header_parts[1], "header") if header_parts.size == 2
        elsif !headers && !stripped.empty?
          body += line
        end
      end

      # Flush the final request (files usually have no trailing `###`).
      commit.call
    end
  rescue
  end

  results
})
