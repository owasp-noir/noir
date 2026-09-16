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
        ob_puts curl_for(method, baked, endpoint.params)
      end
    end
  end

  private def curl_for(method : String, baked, params : Array(Param)) : String
    file_fields = [] of Tuple(String, String)
    text_fields = [] of Tuple(String, String)
    params.each do |param|
      case param.request_type
      when "file"
        file_fields << {param.name, param.value}
      when "form"
        text_fields << {param.name, param.value}
      end
    end

    if file_fields.empty?
      CurlCommand.build(method, baked[:url], baked[:body], baked[:body_type], baked[:header], baked[:cookie])
    else
      CurlCommand.build_multipart(method, baked[:url], text_fields, file_fields, baked[:header], baked[:cookie])
    end
  end
end
