require "../models/output_builder"
require "../models/endpoint"
require "../models/openapi_coverage"

@[Noir::OutputFormat(name: "json", description: "JSON", order: 30, structured: true)]
class OutputBuilderJson < OutputBuilder
  property openapi_coverage : Noir::OpenAPICoverage?

  def print(endpoints : Array(Endpoint), passive_results : Array(PassiveScanResult) = [] of PassiveScanResult)
    # `errors` is emitted even when empty. `"errors": []` is the assertion a
    # CI consumer needs — "every analyzer ran" — and an absent key can't make
    # it, since it reads the same as an older Noir that never reported one.
    document = report_document(endpoints, passive_results)
    if coverage = @openapi_coverage
      ob_puts document.merge({"coverage" => {openapi: coverage.summary(analyzer_failures)}}).to_json
    else
      ob_puts document.to_json
    end
  end
end
