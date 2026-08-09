require "../models/output_builder"
require "../models/endpoint"

@[Noir::OutputFormat(name: "only-param", description: "Only parameters", order: 180)]
class OutputBuilderOnlyParam < OutputBuilder
  # Excluded rather than an allow-list of what to print. This format exists to
  # feed parameter fuzzers, so the question is which inputs *aren't* wanted:
  # headers and cookies have their own `-f only-header` / `-f only-cookie`,
  # and a path param is a URL segment rather than a parameter to submit.
  #
  # It used to be the other way round — an allow-list of six types — and every
  # type outside it was silently dropped: multipart `file` fields, an `xml`
  # request body, Android intent `extra`s. That is the same failure the `body`
  # alias fix hit, one layer up, and a deny-list means a param type a new
  # analyzer introduces shows up here by default instead of vanishing.
  EXCLUDED_TYPES = Set{"header", "cookie", "path"}

  def print(endpoints : Array(Endpoint))
    common_params = [] of String

    endpoints.each do |endpoint|
      endpoint.params.each do |param|
        # `request_type`, not `param_type`: the canonical bucket is what every
        # consumer dispatches on (see `Param#request_type`). Fourteen analyzers
        # spell a body field `body` rather than `json`, and matching on the raw
        # `param_type` dropped every one of them — 82 params across the fixture
        # tree were invisible here while `-f plain` and `-f curl` (which bake
        # through `request_type`) showed them.
        unless EXCLUDED_TYPES.includes? param.request_type
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
