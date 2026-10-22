require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "only-cookie", description: "Only cookies", order: 200)]
class OutputBuilderOnlyCookie < OutputBuilder
  def print(endpoints : Array(Endpoint))
    cookies = [] of String
    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if param.param_type == "cookie"
          cookies << param.name
        end
      end
    end

    print_unique(cookies, "No cookies found.")
  end
end
