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
        parsed_url = URI.parse("")

        file.each_line.with_index do |line, index|
          next if line.starts_with?("#") || line.starts_with?("//")

          if line.strip == "###"
            if !endpoint_url.empty? && parsed_url.to_s.includes? url
              details = Details.new(PathInfo.new(path, index + 1))
              results << Endpoint.new(parsed_url.path, method, params, details)
            end
            method = ""
            endpoint_url = ""
            headers = false
            body = ""
            params = [] of Param
            parsed_url = URI.parse("")
            next
          end

          if line.match(/^(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD) (https?:\/\/[^\s]+)/)
            method, endpoint_url = line.split
            headers = true
            parsed_url = URI.parse(endpoint_url)
            if parsed_url.query
              parsed_url.query.to_s.split("&").each do |param|
                key, value = param.split("=")
                params << Param.new(key, value, "query")
              end
            end
          elsif headers && line.strip.empty?
            headers = false
          elsif headers
            header_name, header_value = line.split(": ", 2)
            params << Param.new(header_name, header_value, "header")
          elsif !headers && !line.strip.empty?
            body += line
          end

          unless body.empty?
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

          if parsed_url.to_s.includes? url
            details = Details.new(PathInfo.new(path, index + 1))
            results << Endpoint.new(parsed_url.path, method, params, details)
          end
        end
      end
    rescue
    end
  end

  results
})
