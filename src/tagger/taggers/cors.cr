require "../../models/tagger"
require "../../models/endpoint"

class CorsTagger < Tagger
  WORDS = ["origin", "access-control-allow-origin", "access-control-request-method"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "cors"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      endpoint.params.each do |param|
        tmp_params.push param.name.to_s.downcase
      end

      words_set = Set.new(WORDS)
      tmp_params_set = Set.new(tmp_params)
      intersection = words_set & tmp_params_set

      # Check that at least three parameters match.
      check = intersection.size.to_i >= 1

      if check
        tag = Tag.new("cors", "CORS endpoint enabling cross-origin requests, allowing web applications from different domains to interact.", "CORS")
        endpoint.add_tag(tag)
      end
    end
  end
end
