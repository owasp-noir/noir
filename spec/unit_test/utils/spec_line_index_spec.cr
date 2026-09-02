require "../../spec_helper"
require "../../../src/utils/spec_line_index"

YAML_DOC = <<-YAML
  # a comment
  openapi: 3.0.0
  info:
    title: t
  paths:
    /pets:
      get:
        summary: list
      post:
        summary: create
    /pets/{id}:
      delete:
        summary: remove
  components:
    schemas:
      Pet:
        type: object
  YAML

JSON_DOC = <<-JSON
  {
    "openapi": "3.0.0",
    "paths": {
      "/pets": {
        "get": { "summary": "list" },
        "post": { "summary": "create" }
      },
      "/pets/{id}": {
        "delete": { "summary": "remove" }
      }
    }
  }
  JSON

describe Noir::SpecLineIndex do
  describe ".yaml" do
    it "reports the line each operation key is declared on" do
      index = Noir::SpecLineIndex.yaml(YAML_DOC, "paths")
      index.line("paths").should eq 5
      index.line("paths", "/pets").should eq 6
      index.line("paths", "/pets", "get").should eq 7
      index.line("paths", "/pets", "post").should eq 9
      index.line("paths", "/pets/{id}").should eq 11
      index.line("paths", "/pets/{id}", "delete").should eq 12
    end

    it "indexes only the requested root" do
      index = Noir::SpecLineIndex.yaml(YAML_DOC, "paths")
      index.line("components").should be_nil
      index.line("components", "schemas").should be_nil
    end

    it "stops at max_depth" do
      index = Noir::SpecLineIndex.yaml(YAML_DOC, "paths", max_depth: 1)
      index.line("paths", "/pets").should eq 6
      index.line("paths", "/pets", "get").should be_nil
    end

    # A stray tab on an otherwise-blank line makes libyaml reject the
    # document; `parse_yaml` recovers it by blanking such lines, and the
    # index has to follow or every operation after the tab loses its line.
    it "recovers the same lines from a document with a stray tab" do
      tabbed = "paths:\n  /w:\n    get:\n      description: |-\n\t\n        text\n    post:\n      summary: c\n"
      index = Noir::SpecLineIndex.yaml(tabbed, "paths")
      index.line("paths", "/w", "get").should eq 3
      index.line("paths", "/w", "post").should eq 7
    end

    it "returns an empty index for text that is not a mapping" do
      Noir::SpecLineIndex.yaml("- 1\n- 2\n", "paths").empty?.should be_true
    end
  end

  describe ".json" do
    it "reports the line each operation key is declared on" do
      index = Noir::SpecLineIndex.json(JSON_DOC, "paths")
      index.line("paths").should eq 3
      index.line("paths", "/pets").should eq 4
      index.line("paths", "/pets", "get").should eq 5
      index.line("paths", "/pets", "post").should eq 6
      index.line("paths", "/pets/{id}", "delete").should eq 9
    end

    # The key, not whatever token the parser has reached by the time the
    # value is in hand.
    it "reports the key line when the value opens on a later line" do
      doc = "{\n  \"paths\":\n  {\n    \"/a\"\n    :\n    {\n      \"get\"\n      :\n      {}\n    }\n  }\n}"
      index = Noir::SpecLineIndex.json(doc, "paths")
      index.line("paths", "/a").should eq 4
      index.line("paths", "/a", "get").should eq 7
    end

    it "returns an empty index for malformed JSON" do
      Noir::SpecLineIndex.json("{oops", "paths").empty?.should be_true
    end
  end
end
