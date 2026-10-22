require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

# The mirror image of the graphql_sdl detector: the same three extensions,
# claimed only when the document carries a named top-level *operation* rather
# than schema declarations. The two must not claim each other's documents —
# they read the same files, so that is the failure mode closest to hand.
describe "Detect GraphQL operation documents" do
  options = create_test_options
  instance = Detector::Specification::GraphqlOperation.new options

  before_each { CodeLocator.instance.clear_all }
  after_each { CodeLocator.instance.clear_all }

  it ".graphql with a named query" do
    content = <<-GRAPHQL
      query GetUser($id: ID!) {
        user(id: $id) { name }
      }
      GRAPHQL

    instance.detect("queries/GetUser.graphql", content).should be_true
  end

  it ".gql with a named mutation" do
    content = <<-GRAPHQL
      mutation CreateUser($name: String!) {
        createUser(name: $name) { id }
      }
      GRAPHQL

    instance.detect("ops.gql", content).should be_true
  end

  it "registers the path for the analyzer pass" do
    instance.detect("queries/GetUser.graphql", "query GetUser { user { id } }")

    CodeLocator.instance.all(Noir::LocatorKeys::GRAPHQL_OPERATION)
      .should contain "queries/GetUser.graphql"
  end

  it "rejects an SDL schema document, which belongs to graphql_sdl" do
    content = <<-GRAPHQL
      type Query {
        user(id: ID!): User
      }
      GRAPHQL

    instance.detect("schema.graphql", content).should be_false
  end

  # `schema { query: Root }` maps a root type; the `query` there is not an
  # operation keyword, and reading it as one would claim every federated SDL
  # document in the tree.
  it "rejects a schema block" do
    content = <<-GRAPHQL
      schema {
        query: Root
      }
      GRAPHQL

    instance.detect("schema.graphql", content).should be_false
  end

  # `.graphqls` is SDL-only by convention. Keeping it off the extension list
  # is what stops the two detectors overlapping on the one extension that is
  # unambiguous.
  it "ignores .graphqls even when it carries an operation" do
    instance.detect("schema.graphqls", "query GetUser { user { id } }").should be_false
  end

  it "ignores an unrelated extension" do
    instance.detect("app.js", "query GetUser { user { id } }").should be_false
  end

  # An anonymous operation carries no name to report, so the parser produces
  # nothing from it — and a detector that claimed the file anyway would put a
  # technology in the report with no endpoints behind it.
  it "rejects an anonymous operation" do
    instance.detect("anon.graphql", "{ user { id } }").should be_false
  end
end
