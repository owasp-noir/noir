require "../../models/analyzer"

class AnalyzerHar < Analyzer
  def analyze
    locator = CodeLocator.instance
    har_files = locator.all("har-path")

    if har_files.is_a?(Array(String)) && @url != ""
      har_files.each do |har_file|
        if File.exists?(har_file)
          data = HAR.from_file(har_file)
          logger.debug "Open #{har_file} file"
          data.entries.each do |entry|
            if entry.request.url.includes? @url
              path = entry.request.url.to_s.gsub(@url, "")
              endpoint = Endpoint.new(path, entry.request.method)

              entry.request.query_string.each do |query|
                endpoint.params << Param.new(query.name, query.value, "query")
              end

              is_websocket = false
              entry.request.headers.each do |header|
                endpoint.params << Param.new(header.name, header.value, "header")
                if header.name == "Upgrade" && header.value == "websocket"
                  is_websocket = true
                end
              end

              entry.request.cookies.each do |cookie|
                endpoint.params << Param.new(cookie.name, cookie.value, "cookie")
              end

              post_data = entry.request.post_data
              if post_data
                params = post_data.params
                mime_type = post_data.mime_type
                param_type = "body"
                if mime_type == "application/json"
                  param_type = "json"
                end
                if params
                  params.each do |param|
                    endpoint.params << Param.new(param.name, param.value.to_s, param_type)
                  end
                end
              end

              details = Details.new(PathInfo.new(har_file, 0))
              endpoint.set_details(details)
              if is_websocket
                endpoint.set_protocol "ws"
              end
              @result << endpoint
            end
          end
        end
      end
    end

    @result
  end
end

def analyzer_har(options : Hash(String, YAML::Any))
  instance = AnalyzerHar.new(options)
  instance.analyze
end
