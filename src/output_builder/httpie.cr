require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "../utils/curl_command"
require "json"

@[Noir::OutputFormat(name: "httpie", description: "HTTPie commands", order: 100)]
class OutputBuilderHttpie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      option_parts = [] of String
      request_items = [] of String

      has_file = endpoint.params.any? { |p| p.request_type == "file" }

      if has_file
        # File uploads need `--form` with `field@filename`. Without this,
        # HTTPie dropped every `param_type: file` the same way curl did.
        option_parts << "--form"
        endpoint.params.each do |param|
          case param.request_type
          when "form"
            request_items << CurlCommand.shell_quote("#{item_name(param.name)}=#{param.value}")
          when "file"
            filename = param.value.empty? ? param.name : param.value
            request_items << CurlCommand.shell_quote("#{item_name(param.name)}@#{filename}")
          end
        end
      elsif !baked[:body].empty?
        if baked[:body_type] == "json"
          begin
            json_data = JSON.parse(baked[:body])
            if json_data.as_h?
              json_data.as_h.each do |key, value|
                if value.raw.is_a?(String)
                  request_items << CurlCommand.shell_quote("#{item_name(key, json: true)}=#{value.as_s}")
                else
                  request_items << CurlCommand.shell_quote("#{item_name(key, json: true)}:=#{value.to_json}")
                end
              end
            else
              option_parts << "--raw"
              option_parts << CurlCommand.shell_quote(baked[:body])
              request_items << CurlCommand.shell_quote("Content-Type:application/json")
            end
          rescue
            option_parts << "--raw"
            option_parts << CurlCommand.shell_quote(baked[:body])
            request_items << CurlCommand.shell_quote("Content-Type:application/json")
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
            request_items << CurlCommand.shell_quote("#{item_name(param.name)}=#{param.value}")
          end
        end
      end

      expand_synthetic_http_methods(endpoint.method).each do |method|
        parts = ["http"]
        parts.concat(option_parts)
        parts << CurlCommand.shell_quote(method)
        parts << CurlCommand.shell_quote(baked[:url])
        parts.concat(request_items)

        baked[:header].each do |header|
          parts << CurlCommand.shell_quote(header)
        end

        unless baked[:cookie].empty?
          cookie_value = baked[:cookie].join("; ")
          parts << CurlCommand.shell_quote("Cookie:#{cookie_value}")
        end

        ob_puts parts.join(" ")
      end
    end
  end

  # HTTPie splits a request item at its first `=`, `:`, `@` or `;`, so a
  # field named `@type` (JSON-LD), `a:b`, `c=d` or `a;b` came out as a file
  # upload, a header, a truncated field or an "Invalid item" error. A
  # backslash makes the next separator literal. JSON items also go through
  # HTTPie's nested-JSON syntax, where `a[b]` builds an object — so there,
  # and only there, `[`/`]` are escaped too (under `--form` HTTPie would keep
  # the backslash).
  private def item_name(name : String, json : Bool = false) : String
    name.gsub(json ? /[=:@;\[\]]/ : /[=:@;]/) { |sep| "\\#{sep}" }
  end
end
