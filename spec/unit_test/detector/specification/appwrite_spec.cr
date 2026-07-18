require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Appwrite config" do
  options = create_test_options
  instance = Detector::Specification::Appwrite.new options

  it "detects an appwrite.json with collections" do
    content = <<-JSON
      {
        "projectId": "demo",
        "collections": [
          { "$id": "posts", "databaseId": "blog", "attributes": [] }
        ]
      }
      JSON

    instance.detect("appwrite.json", content).should be_true
  end

  it "detects an appwrite.config.json with the >=1.6 tables key" do
    content = <<-JSON
      {
        "projectId": "demo",
        "tablesDB": [{ "$id": "shop" }],
        "tables": [{ "$id": "orders", "databaseId": "shop", "columns": [] }]
      }
      JSON

    instance.detect("appwrite.config.json", content).should be_true
  end

  it "detects a functions-only config" do
    content = %({"projectId": "demo", "functions": [{"$id": "hello"}]})
    instance.detect("appwrite.json", content).should be_true
  end

  # A JSON carrying "collections" is a common shape (Sanity exports,
  # Postman-adjacent tooling, Firestore rules dumps). projectId is what
  # makes it Appwrite.
  it "ignores a JSON with collections but no projectId" do
    content = <<-JSON
      {
        "collections": [
          { "$id": "posts", "attributes": [] }
        ]
      }
      JSON

    instance.detect("appwrite.json", content).should be_false
  end

  it "ignores a projectId-only config with no resource family" do
    instance.detect("appwrite.json", %({"projectId": "demo"})).should be_false
  end

  it "ignores an Appwrite-shaped document under a different filename" do
    content = %({"projectId": "demo", "collections": []})
    instance.detect("config.json", content).should be_false
    instance.detect("package.json", content).should be_false
  end

  it "ignores malformed JSON" do
    instance.detect("appwrite.json", %({"projectId": "demo", )).should be_false
  end

  it "ignores a non-object root" do
    instance.detect("appwrite.json", %([{"projectId": "demo"}])).should be_false
  end

  it "registers the path in the code locator" do
    content = %({"projectId": "demo", "collections": []})

    locator = CodeLocator.instance
    locator.clear "appwrite-config"
    instance.detect("appwrite.json", content)
    locator.all("appwrite-config").should eq(["appwrite.json"])
  end
end
