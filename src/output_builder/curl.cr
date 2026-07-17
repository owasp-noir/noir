require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "../utils/curl_command"

class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      expand_synthetic_http_methods(endpoint.method).each do |method|
        ob_puts CurlCommand.build(method, baked[:url], baked[:body], baked[:body_type], baked[:header], baked[:cookie])
      end
    end
  end
end
