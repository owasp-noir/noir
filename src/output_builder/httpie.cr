require "../models/output_builder"
require "../models/endpoint"
require "json"

class OutputBuilderHttpie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      baked = bake_endpoint(endpoint.url, endpoint.params)

      parts = ["http"]
      request_items = [] of String

      unless baked[:body].empty?
        if baked[:body_type] == "json"
          begin
            json_data = JSON.parse(baked[:body])
            if json_data.as_h?
              json_data.as_h.each do |key, value|
                if value.raw.is_a?(String)
                  request_items << shell_quote("#{key}=#{value.as_s}")
                else
                  request_items << shell_quote("#{key}:=#{value.to_json}")
                end
              end
            else
              parts << "--raw"
              parts << shell_quote(baked[:body])
              request_items << shell_quote("Content-Type:application/json")
            end
          rescue
            parts << "--raw"
            parts << shell_quote(baked[:body])
            request_items << shell_quote("Content-Type:application/json")
          end
        else
          parts << "--form"
          form_parts = baked[:body].split('&')
          form_parts.each do |part|
            if part.includes?('=')
              request_items << shell_quote(part)
            end
          end
        end
      end

      parts << shell_quote(endpoint.method)
      parts << shell_quote(baked[:url])
      parts.concat(request_items)

      baked[:header].each do |header|
        parts << shell_quote(header)
      end

      unless baked[:cookie].empty?
        cookie_value = baked[:cookie].join("; ")
        parts << shell_quote("Cookie:#{cookie_value}")
      end

      ob_puts parts.join(" ")
    end
  end

  private def shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
  end
end
