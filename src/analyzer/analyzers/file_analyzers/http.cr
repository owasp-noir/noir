require "base64"
require "../../../models/analyzer"
require "../../../models/endpoint"
require "json"

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

        file.each_line.with_index do |line, index|
          if line.match(/^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD) (https?:\/\/[^\s]+)/)
            method, endpoint_url = line.split
            headers = true
          elsif headers && line.strip.empty?
            headers = false
            parsed_url = URI.parse(endpoint_url)
            if parsed_url.to_s.includes? url
              details = Details.new(PathInfo.new(path, index + 1))
              results << Endpoint.new(parsed_url.path, method, params, details)
            end
          elsif headers
            header_name, header_value = line.split(": ", 2)
            params << Param.new(header_name, header_value, "header")
          elsif !headers && !line.strip.empty?
            body += line
          end
        end

        unless body.empty?
          puts body
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
      end
    rescue
    end
  end

  results
})
