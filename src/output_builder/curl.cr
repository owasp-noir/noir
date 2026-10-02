require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "../utils/curl_command"

@[Noir::OutputFormat(name: "curl", description: "cURL commands", order: 90)]
class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? # mobile deep links / CLI commands aren't HTTP requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      expand_synthetic_http_methods(endpoint.method).each do |method|
        ob_puts CurlCommand.for_endpoint(method, baked, endpoint.params)
      end
    end
  end
end
