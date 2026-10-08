require "../../../models/detector"

module Detector::Ruby
  # Detects graphql-ruby servers: a class subclassing `GraphQL::Schema` or one
  # of its members (`GraphQL::Schema::Object`, `::RelayClassicMutation`,
  # `::Resolver`, ...). Client-side gems (graphql-client) never subclass
  # these, so a bare `require "graphql"` is not enough.
  class Graphql < Detector
    detector_for "ruby_graphql", extensions: %w[.rb]

    SCHEMA_SUBCLASS = /<\s*(?:::)?GraphQL::Schema\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".rb")
      content_matches?(file_contents, SCHEMA_SUBCLASS)
    end
  end
end
