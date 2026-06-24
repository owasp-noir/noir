require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"

class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      expand_synthetic_http_methods(endpoint.method).each do |method|
        parts = ["curl", "-i", "-X", shell_quote(method), shell_quote(baked[:url])]

        unless baked[:body].empty?
          if baked[:body_type] == "json"
            parts << "--data-raw"
            parts << shell_quote(baked[:body])
            parts << "-H"
            parts << shell_quote("Content-Type: application/json")
          else
            parts << "--data-raw"
            parts << shell_quote(baked[:body])
            parts << "-H"
            parts << shell_quote("Content-Type: application/x-www-form-urlencoded")
          end
        end

        baked[:header].each do |header|
          parts << "-H"
          parts << shell_quote(header)
        end

        baked[:cookie].each do |cookie|
          parts << "--cookie"
          parts << shell_quote(cookie)
        end

        ob_puts parts.join(" ")
      end
    end
  end

  private def shell_quote(str : String) : String
    "'#{str.gsub("'", "'\\''")}'"
  end
end
