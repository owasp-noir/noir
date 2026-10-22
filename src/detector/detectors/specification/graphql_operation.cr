require "../../../models/detector"
require "../../../models/code_locator"
require "../../../miniparsers/graphql_operation_parser"

module Detector::Specification
  class GraphqlOperation < Detector
    # Registers every operation document for the analyzer pass, so it must
    # keep running after the first match.
    #
    # `.graphqls` is SDL-only by convention and is deliberately absent: the
    # extension list is the same one the file-analyzer hook this replaced
    # tested for, so the set of files that can produce an endpoint is
    # unchanged.
    detector_for "graphql_operation", extensions: %w[.graphql .gql], idempotent: false

    # The claim test *is* the analyzer's parse, stopped at the first
    # operation. A cheaper keyword sniff would have to be either looser than
    # the parser (claiming SDL schemas, which belong to `graphql_sdl`) or
    # tighter (dropping documents the analyzer can read), and either way the
    # detector and the analyzer would disagree about the same file.
    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless Noir::GraphqlOperationParser.operation_document?(file_contents)

      CodeLocator.instance.push(Noir::LocatorKeys::GRAPHQL_OPERATION, filename)
      true
    end
  end
end
