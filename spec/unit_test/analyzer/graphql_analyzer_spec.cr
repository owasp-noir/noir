require "../../spec_helper" # Common for Crystal spec setup
require "../../../src/models/analyzer"
require "../../../src/models/endpoint" # Includes Param, Details, PathInfo
require "../../../src/analyzer/analyzers/file_analyzers/graphql_analyzer" # This will register the hook

describe "GraphQL Analyzer Logic (InternalGraphqlParser.parse_content)" do
  # The file containing InternalGraphqlParser is loaded via the require statement at the top.
  # We will call InternalGraphqlParser.parse_content directly.

  sample_graphql_content = <<-GRAPHQL
    # This is a comment
    query GetHero {
      hero {
        name
        friends { name }
      }
    }

    mutation CreateReviewForEpisode($ep: Episode!, $review: ReviewInput!) {
      createReview(episode: $ep, review: $review) {
        stars
        commentary
      }
    }

    subscription OnNewReview {
      newReview {
        id
        stars
        commentary
      }
    }

    query AnotherQuery{field} # Test multiple queries and no body
  GRAPHQL

  # Note: The original subtask mentioned that the hook itself should filter for .graphql files.
  # The InternalGraphqlParser.parse_content method itself does not (and should not) filter by filename,
  # as it's concerned with parsing content. The hook that calls it is responsible for file filtering.
  # These tests will focus on the content parsing logic of parse_content.

  it "processes an empty content string" do
    endpoints = InternalGraphqlParser.parse_content("empty.graphql", "")
    endpoints.should be_empty
  end

  it "processes content with no operations" do
    content_no_ops = <<-GRAPHQL
      # Only comments
      # type User { name: String }
    GRAPHQL
    endpoints = InternalGraphqlParser.parse_content("no_ops.graphql", content_no_ops)
    endpoints.should be_empty
  end

  describe "when processing valid GraphQL content" do
    path = "example.graphql" # Define path as a local variable
    # Calculate endpoints once for this describe block, making it a local variable
    endpoints = InternalGraphqlParser.parse_content(path, sample_graphql_content)

    it "extracts the correct number of endpoints" do
      endpoints.size.should eq(4)
    end

    context "for the GetHero query" do
      endpoint = endpoints.find { |ep| ep.params.first?.try(&.value.includes?("GetHero")) }

      it "creates an endpoint" do
        endpoint.should_not be_nil
      end

      it "sets the correct URL and method" do
        endpoint.not_nil!.url.should eq("/graphql")
        endpoint.not_nil!.method.should eq("POST")
      end

      it "adds correct parameter" do
        param = endpoint.not_nil!.params.first?
        param.should_not be_nil
        param.not_nil!.param_type.should eq("json")
        param.not_nil!.name.should eq("graphql_operation_query_GetHero") # Adjusted to match current naming

        # Parse the JSON string value for checking
        json_value = JSON.parse(param.not_nil!.value)
        json_value["query"]?.should eq("GetHero")
      end

      it "sets correct path info" do
        details = endpoint.not_nil!.details
        details.code_paths.size.should eq(1)
        path_info = details.code_paths.first?
        path_info.should_not be_nil
        path_info.not_nil!.path.should eq(path)
        path_info.not_nil!.line.should eq(2) # Line numbers are 1-based, query GetHero is on line 2
      end
    end

    context "for the CreateReviewForEpisode mutation" do
      endpoint = endpoints.find { |ep| ep.params.first?.try(&.value.includes?("CreateReviewForEpisode")) }

      it "creates an endpoint" do
        endpoint.should_not be_nil
      end

      it "sets the correct URL and method" do
        endpoint.not_nil!.url.should eq("/graphql")
        endpoint.not_nil!.method.should eq("POST")
      end

      it "adds correct parameter" do
        param = endpoint.not_nil!.params.first?
        param.should_not be_nil
        param.not_nil!.param_type.should eq("json")
        param.not_nil!.name.should eq("graphql_operation_mutation_CreateReviewForEpisode")

        json_value = JSON.parse(param.not_nil!.value)
        json_value["mutation"]?.should eq("CreateReviewForEpisode")
      end

      it "sets correct path info" do
        details = endpoint.not_nil!.details
        path_info = details.code_paths.first?
        path_info.not_nil!.path.should eq(path)
        path_info.not_nil!.line.should eq(9) # mutation CreateReviewForEpisode is on line 9
      end
    end

    context "for the OnNewReview subscription" do
      endpoint = endpoints.find { |ep| ep.params.first?.try(&.value.includes?("OnNewReview")) }

      it "creates an endpoint" do
        endpoint.should_not be_nil
      end

      it "sets correct parameter" do
        param = endpoint.not_nil!.params.first?
        param.not_nil!.param_type.should eq("json")
        param.not_nil!.name.should eq("graphql_operation_subscription_OnNewReview")

        json_value = JSON.parse(param.not_nil!.value)
        json_value["subscription"]?.should eq("OnNewReview")
      end

      it "sets correct path info" do
        details = endpoint.not_nil!.details
        path_info = details.code_paths.first?
        path_info.not_nil!.path.should eq(path)
        path_info.not_nil!.line.should eq(16) # subscription OnNewReview is on line 16
      end
    end

    context "for the AnotherQuery query" do
      endpoint = endpoints.find { |ep| ep.params.first?.try(&.value.includes?("AnotherQuery")) }

      it "creates an endpoint" do
        endpoint.should_not be_nil
      end

      it "sets correct parameter" do
        param = endpoint.not_nil!.params.first?
        param.not_nil!.param_type.should eq("json")
        param.not_nil!.name.should eq("graphql_operation_query_AnotherQuery")

        json_value = JSON.parse(param.not_nil!.value)
        json_value["query"]?.should eq("AnotherQuery")
      end

      it "sets correct path info" do
        details = endpoint.not_nil!.details
        path_info = details.code_paths.first?
        path_info.not_nil!.path.should eq(path)
        path_info.not_nil!.line.should eq(24) # Corrected: query AnotherQuery is on line 24
      end
    end
  end

  # File read errors are handled by the hook, not by parse_content directly, so no test for that here.
end
