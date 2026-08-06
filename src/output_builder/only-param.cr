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
        # `request_type`, not `param_type`: the canonical bucket is what every
        # consumer dispatches on (see `Param#request_type`). Fourteen analyzers
        # spell a body field `body` rather than `json`, and matching on the raw
        # `param_type` dropped every one of them — 82 params across the fixture
        # tree were invisible here while `-f plain` and `-f curl` (which bake
        # through `request_type`) showed them.
        if targets.includes? param.request_type
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
