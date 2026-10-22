require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "only-header", description: "Only headers", order: 190)]
class OutputBuilderOnlyHeader < OutputBuilder
  def print(endpoints : Array(Endpoint))
    headers = [] of String
    cookie = false
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if param.param_type == "header"
          headers << param.name
        elsif param.param_type == "cookie"
          cookie = true
        end
      end
    end

    if cookie
      headers << "Cookie"
    end

    print_unique(headers, "No headers found.")
  end
end
