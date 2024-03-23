require "../models/tagger"
require "../models/endpoint"

class HuntParamTagger < Tagger
  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      endpoint.params.each do |_|
        # TODO
      end
    end

    endpoints
  end
end
