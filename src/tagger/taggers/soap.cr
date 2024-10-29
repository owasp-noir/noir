require "../../models/tagger"
require "../../models/endpoint"

class SoapTagger < Tagger
  WORDS = ["soapaction"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "soap"
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
        tag = Tag.new("soap", "SOAP endpoint for XML-based web service communication, supporting structured information exchanges across network applications.", "SOAP")
        endpoint.add_tag(tag)
      end
    end
  end
end
