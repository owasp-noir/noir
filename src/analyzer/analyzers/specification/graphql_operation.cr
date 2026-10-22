require "../../engines/specification_engine"
require "../../../miniparsers/graphql_operation_parser"

module Analyzer::Specification
  # Emits one `POST /graphql` endpoint per named top-level operation found in
  # a GraphQL operation document (`query Foo { … }` in a `.graphql` / `.gql`
  # file). The optimizer merges them on method + url, so a project ends up
  # with one endpoint carrying one param per operation.
  #
  # This used to be a `FileAnalyzer` hook, which put it outside the tech
  # registry: its endpoints carried `"technology": null` and, because the
  # file analyzer runs unconditionally, they were returned by every
  # `--only-techs <T>` run as well — six technologies on the hoppscotch
  # corpus each reported one endpoint their analyzer had not produced.
  # Registering it as a technology is what puts it back under the same
  # detection and tech-selection rules as everything else.
  #
  # SDL schema documents are `graphql_sdl`'s; the parser reports nothing for
  # them, and the detector only registers files it would produce something
  # from.
  class GraphqlOperation < SpecificationEngine
    analyzer_for "graphql_operation"

    def analyze
      each_spec_file(Noir::LocatorKeys::GRAPHQL_OPERATION) do |path|
        content = read_file_content(path)
        Noir::GraphqlOperationParser.parse_content(path, content).each { |ep| @result << ep }
      end

      @result
    end
  end
end
