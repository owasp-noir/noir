require "../../../models/analyzer"
require "./common"
require "./minimal_api_support"

module Analyzer::CSharp
  class MinimalApis < Analyzer
    include Common
    include MinimalApiSupport

    def analyze
      analyze_minimal_api_files(callees_needed?)
      @result
    end
  end
end
