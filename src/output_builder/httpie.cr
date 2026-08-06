require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "json"

class OutputBuilderHttpie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      option_parts = [] of String
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
              option_parts << "--raw"
              option_parts << shell_quote(baked[:body])
              request_items << shell_quote("Content-Type:application/json")
            end
          rescue
            option_parts << "--raw"
            option_parts << shell_quote(baked[:body])
            request_items << shell_quote("Content-Type:application/json")
          end
        else
          option_parts << "--form"
          # Read the params directly instead of re-splitting the `k=v&k=v`
          # body `bake_endpoint` joined them into. That round trip has no way
          # to tell a separator from a `&` inside a value, so a form param
          # `note=a&b=c` came out as `'note=a' 'b=c'` — the real value
          # truncated and a field named `b` that the endpoint never had.
          # httpie takes everything after the first `=` as the value, so one
          # shell-quoted item per param is exact.
          endpoint.params.each do |param|
            next unless param.request_type == "form"
            request_items << shell_quote("#{param.name}=#{param.value}")
          end
        end
      end

      expand_synthetic_http_methods(endpoint.method).each do |method|
        parts = ["http"]
        parts.concat(option_parts)
        parts << shell_quote(method)
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
  end

  private def shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
  end
end
