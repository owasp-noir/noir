require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/appwrite"

private def analyze_appwrite(content : String)
  path = File.tempname("appwrite", ".json")
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear "appwrite-config"
  locator.push "appwrite-config", path

  options = create_test_options
  analyzer = Analyzer::Specification::Appwrite.new options
  analyzer.analyze
ensure
  locator = CodeLocator.instance
  locator.clear "appwrite-config"
  File.delete(path) if path && File.exists?(path)
end

describe "Appwrite Analyzer" do
  it "expands a collection into the documents CRUD family" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "collections": [
          { "$id": "posts", "databaseId": "blog", "attributes": [] }
        ]
      }
      JSON

    base = "/v1/databases/blog/collections/posts/documents"
    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"GET", base})
    pairs.should contain({"POST", base})
    pairs.should contain({"GET", "#{base}/{documentId}"})
    pairs.should contain({"PATCH", "#{base}/{documentId}"})
    pairs.should contain({"DELETE", "#{base}/{documentId}"})
    endpoints.size.should eq(5)
  end

  it "wraps attributes in the data object and maps their types" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "collections": [
          {
            "$id": "posts",
            "databaseId": "blog",
            "attributes": [
              { "key": "title", "type": "string", "array": false },
              { "key": "views", "type": "integer", "array": false },
              { "key": "tags", "type": "string", "array": true }
            ]
          }
        ]
      }
      JSON

    create = endpoints.find! { |e| e.method == "POST" }
    title = create.params.find! { |p| p.name == "data.title" }
    title.param_type.should eq("json")
    title.value.should eq("string")
    create.params.find! { |p| p.name == "data.views" }.value.should eq("int")
    # An array attribute is hinted by arity, not by its element type.
    create.params.find! { |p| p.name == "data.tags" }.value.should eq("array")
    # The bare attribute name is never a wire param - Appwrite filters
    # through ?queries[], so `title` alone must not appear.
    create.params.none? { |p| p.name == "title" }.should be_true
  end

  it "carries the parsed projectId as a concrete header value" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "my_project",
        "collections": [{ "$id": "posts", "databaseId": "blog", "attributes": [] }]
      }
      JSON

    header = endpoints.first.params.find! { |p| p.name == "X-Appwrite-Project" }
    header.param_type.should eq("header")
    header.value.should eq("my_project")
  end

  it "emits the tables/rows family instead of collections when tables is present" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "tables": [
          { "$id": "orders", "databaseId": "shop", "columns": [{ "key": "sku", "type": "string" }] }
        ]
      }
      JSON

    urls = endpoints.map(&.url).uniq!
    urls.should contain("/v1/tablesdb/shop/tables/orders/rows")
    urls.should contain("/v1/tablesdb/shop/tables/orders/rows/{rowId}")
    # The <=1.5 vocabulary must not be emitted alongside - it would 404.
    endpoints.none?(&.url.includes?("/collections/")).should be_true
    endpoints.find! { |e| e.method == "POST" }.params.any? { |p| p.name == "rowId" }.should be_true
  end

  it "emits function execution endpoints" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "functions": [{ "$id": "sendMail", "runtime": "node-18.0" }]
      }
      JSON

    pairs = endpoints.map { |e| {e.method, e.url} }
    pairs.should contain({"POST", "/v1/functions/sendMail/executions"})
    pairs.should contain({"GET", "/v1/functions/sendMail/executions"})
    pairs.should contain({"GET", "/v1/functions/sendMail/executions/{executionId}"})
  end

  it "emits storage bucket file endpoints" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "buckets": [{ "$id": "avatars", "name": "Avatars" }]
      }
      JSON

    urls = endpoints.map(&.url)
    urls.should contain("/v1/storage/buckets/avatars/files")
    urls.should contain("/v1/storage/buckets/avatars/files/{fileId}")
    urls.should contain("/v1/storage/buckets/avatars/files/{fileId}/download")
    upload = endpoints.find! { |e| e.method == "POST" }
    upload.params.any? { |p| p.name == "file" && p.param_type == "form" }.should be_true
  end

  # A collection without databaseId cannot produce a valid URL -
  # /v1/collections/{id}/documents is not a real Appwrite route.
  it "skips a collection missing its databaseId" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "collections": [{ "$id": "orphan", "attributes": [] }]
      }
      JSON

    endpoints.size.should eq(0)
  end

  it "tags each endpoint with its operation kind" do
    endpoints = analyze_appwrite <<-JSON
      {
        "projectId": "demo",
        "collections": [{ "$id": "posts", "databaseId": "blog", "attributes": [] }]
      }
      JSON

    list = endpoints.find! { |e| e.method == "GET" && !e.url.includes?("{") }
    list.tags.any? { |t| t.name == "appwrite" && t.description == "collection-list:posts" }.should be_true
  end
end
