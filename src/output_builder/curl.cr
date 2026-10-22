require "../models/output_builder"
require "../models/endpoint"
require "../utils/http_symbols"
require "../utils/curl_command"

@[Noir::OutputFormat(name: "curl", description: "cURL commands", order: 90)]
class OutputBuilderCurl < OutputBuilder
  def print(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      next if endpoint.non_http? || endpoint.regex_path? # deep links, CLI commands and regex routes aren't requests
      baked = bake_endpoint(endpoint.url, endpoint.params)

      expand_synthetic_http_methods(endpoint.method).each do |method|
        ob_puts CurlCommand.for_endpoint(method, baked, endpoint.params)
      end
    end
  end
end
