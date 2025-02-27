require "base64"
require "../../../models/analyzer"
require "../../../models/endpoint"
require "json"

def parse_params(query : String?, params : Array(Param), type : String)
  return unless query
  query.to_s.split("&").each do |param|
    key, value = param.split("=")
    params << Param.new(key, value, type)
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
    body.split("&").each do |param|
      key, value = param.split("=")
      params << Param.new(key, value, "form")
    end
  end
end

def process_line(line : String, index : Int32, path : String, url : String, method : String, endpoint_url : String, headers : Bool, body : String, params : Array(Param), parsed_url : URI, results : Array(Endpoint))
  if line.strip == "###"
    if !endpoint_url.empty? && parsed_url.to_s.includes? url
      details = Details.new(PathInfo.new(path, index + 1))
      results << Endpoint.new(parsed_url.path, method, params, details)
    end
    return "", "", false, "", [] of Param, URI.parse("")
  end

  if line.match(/^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD) (https?:\/\/[^\s]+)/)
    method, endpoint_url = line.split
    headers = true
    parsed_url = URI.parse(endpoint_url)
    parse_params(parsed_url.query, params, "query")
  elsif headers && line.strip.empty?
    headers = false
  elsif headers
    header_name, header_value = line.split(": ", 2)
    params << Param.new(header_name, header_value, "header")
  elsif !headers && !line.strip.empty?
    body += line
  end

  parse_body(body, params)

  if parsed_url.to_s.includes? url
    details = Details.new(PathInfo.new(path, index + 1))
    results << Endpoint.new(parsed_url.path, method, params, details)
  end

  return method, endpoint_url, headers, body, params, parsed_url
end

FileAnalyzer.add_hook(->(path : String, url : String) : Array(Endpoint) {
  results = [] of Endpoint

  if File.extname(path) == ".http"
    begin
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        method = ""
        endpoint_url = ""
        headers = false
        body = ""
        params = [] of Param
        parsed_url = URI.parse("")

        file.each_line.with_index do |line, index|
          next if line.starts_with?("#") || line.starts_with?("//")
          method, endpoint_url, headers, body, params, parsed_url = process_line(line, index, path, url, method, endpoint_url, headers, body, params, parsed_url, results)
        end
      end
    rescue
    end
  end

  results
})
