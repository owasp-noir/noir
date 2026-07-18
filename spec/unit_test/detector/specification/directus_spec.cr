require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Directus snapshot" do
  options = create_test_options
  instance = Detector::Specification::Directus.new options

  snapshot = <<-YAML
    version: 1
    directus: 10.13.0
    vendor: postgres
    collections:
      - collection: posts
        meta:
          singleton: false
        schema:
          name: posts
    fields:
      - collection: posts
        field: title
        type: string
    YAML

  it "detects a snapshot.yaml" do
    instance.detect("snapshot.yaml", snapshot).should be_true
  end

  it "detects a snapshot under a directus/ directory with any name" do
    instance.detect("infra/directus/model.yaml", snapshot).should be_true
  end

  it "detects the JSON snapshot form" do
    content = <<-JSON
      {
        "version": 1,
        "directus": "10.13.0",
        "vendor": "postgres",
        "collections": [{ "collection": "posts", "schema": { "name": "posts" } }],
        "fields": []
      }
      JSON

    instance.detect("snapshot.json", content).should be_true
  end

  # `collections:` + `fields:` is a shape plenty of unrelated tools emit
  # (Sanity exports, MongoDB seeds, CI matrices). The root `directus:`
  # engine-version key is what makes it a Directus snapshot.
  it "ignores a collections/fields document with no root directus key" do
    content = <<-YAML
      version: 1
      collections:
        - collection: posts
          schema:
            name: posts
      fields:
        - collection: posts
          field: title
      YAML

    instance.detect("snapshot.yaml", content).should be_false
  end

  it "ignores a document whose collections carry no collection key" do
    content = <<-YAML
      directus: 10.13.0
      collections:
        - name: posts
        - name: authors
      YAML

    instance.detect("snapshot.yaml", content).should be_false
  end

  it "ignores a snapshot-shaped document under an unrelated filename" do
    instance.detect("config.yaml", snapshot).should be_false
    instance.detect("docker-compose.yml", snapshot).should be_false
  end

  it "ignores unrelated extensions" do
    instance.detect("snapshot.txt", snapshot).should be_false
    instance.detect("snapshot.tsx", snapshot).should be_false
  end

  it "ignores malformed YAML" do
    instance.detect("snapshot.yaml", "directus: 10\ncollections:\n  - : :\n\t bad").should be_false
  end

  it "registers the path in the code locator" do
    locator = CodeLocator.instance
    locator.clear "directus-snapshot"
    instance.detect("snapshot.yaml", snapshot)
    locator.all("directus-snapshot").should eq(["snapshot.yaml"])
  end
end
