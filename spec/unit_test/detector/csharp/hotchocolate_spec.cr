require "../../../spec_helper"
require "../../../../src/detector/detectors/csharp/*"

describe "Detect C# HotChocolate" do
  options = create_test_options
  instance = Detector::CSharp::HotChocolate.new options

  it "detects a HotChocolate namespace import" do
    instance.detect("Query.cs", "using HotChocolate.Types;\n[QueryType]\npublic static class Q {}").should be_true
  end

  it "detects AddGraphQLServer()" do
    instance.detect("Program.cs", "builder.Services.AddGraphQLServer().AddQueryType<Query>();").should be_true
  end

  it "detects the csproj package reference" do
    instance.detect("Api.csproj", "<PackageReference Include=\"HotChocolate.AspNetCore\" Version=\"15.0.0\" />").should be_true
  end

  it "ignores a plain class named Query" do
    instance.detect("Query.cs", "public class Query { public string GetReport(int id) => \"r\"; }").should be_false
  end

  it "ignores unrelated packages" do
    instance.detect("Api.csproj", "<PackageReference Include=\"GraphQL.Server\" />").should be_false
  end
end
