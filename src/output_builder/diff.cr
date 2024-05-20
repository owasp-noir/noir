require "../models/output_builder"
require "../models/endpoint"

class OutputBuilderDiff < OutputBuilder
  def diff(new_entpoint : Endpoint, old_endpoints : Array(Endpoint))
    old_endpoints.each do |old_endpoint|
      if new_entpoint.url == old_endpoint.url && new_entpoint.method == old_endpoint.method
        if new_entpoint.params == old_endpoint.params
          return false
        end
      end
    end
    true
  end

  def print(endpoints : Array(Endpoint), diff_app : NoirRunner)
    @logger.system "============== DIFF =============="
  end
end
