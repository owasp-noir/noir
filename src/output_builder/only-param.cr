require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderOnlyParam < OutputBuilder
  def print(endpoints : Array(Endpoint))
    common_params = [] of String
    # CLI endpoints carry their fuzzable inputs as flag/argument/env params,
    # so include them alongside the HTTP body-ish buckets.
    targets = ["query", "json", "form", "flag", "argument", "env"]

    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        if targets.includes? param.param_type
          common_params << param.name
        end
      end
    end

    unique = common_params.uniq
    if unique.empty?
      @logger.info "No parameters found."
      return
    end
    unique.each do |common_param|
      ob_puts common_param.colorize(:light_green).toggle(@is_color)
    end
  end
end
