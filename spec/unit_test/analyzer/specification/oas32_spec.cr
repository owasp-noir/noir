require "../../../spec_helper"
require "file_utils"
require "json"
require "../../../../src/analyzer/analyzers/specification/oas3"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"

private def analyze_oas3(filename : String, content : String) : Array(Endpoint)
  dir = File.tempname("noir_oas32")
  Dir.mkdir_p(dir)
  path = File.join(dir, filename)
  File.write(path, content)
  CodeLocator.instance.clear_all
  key = filename.ends_with?(".json") ? Noir::LocatorKeys::OAS3_JSON : Noir::LocatorKeys::OAS3_YAML
  CodeLocator.instance.push(key, path)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  Analyzer::Specification::Oas3.new(options).analyze
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir
end

private def json_names(endpoint : Endpoint, type : String) : Array(String)
  endpoint.params.select { |param| param.param_type == type }.map(&.name).sort!
end

describe "OAS 3.2 additionalOperations and discriminators" do
  it "reads additionalOperations and discriminator subtypes from JSON" do
    endpoints = analyze_oas3("openapi.json", <<-JSON)
      {
        "openapi": "3.2.0",
        "info": {"title": "t", "version": "1"},
        "paths": {
          "/trips/{id}": {
            "parameters": [
              {"name": "id", "in": "path", "required": true, "schema": {"type": "string"}},
              {"name": "verbose", "in": "query", "schema": {"type": "boolean"}}
            ],
            "additionalOperations": {
              "SUBSCRIBE": {"operationId": "subscribe-trip", "responses": {"200": {"description": "ok"}}},
              "LINK": {"operationId": "link-trip", "responses": {"200": {"description": "ok"}}}
            }
          },
          "/stations": {"get": {"responses": {"200": {"description": "ok"}}}},
          "/document": {
            "put": {
              "requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Doc"}}}},
              "responses": {"200": {"description": "ok"}}
            }
          },
          "/pet": {
            "put": {
              "requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/Pet"}}}},
              "responses": {"200": {"description": "ok"}}
            }
          }
        },
        "components": {
          "schemas": {
            "Doc": {
              "type": "object",
              "discriminator": {"propertyName": "docType", "mapping": {"article": "#/components/schemas/DocArticle"}},
              "properties": {"docType": {"type": "string"}}
            },
            "DocArticle": {
              "allOf": [
                {"$ref": "#/components/schemas/Doc"},
                {"type": "object", "properties": {"headline": {"type": "string"}}}
              ]
            },
            "Pet": {
              "type": "object",
              "discriminator": {"propertyName": "petType"},
              "properties": {"petType": {"type": "string"}}
            },
            "PetCat": {
              "allOf": [
                {"$ref": "#/components/schemas/Pet"},
                {"type": "object", "properties": {"huntingSkill": {"type": "string"}}}
              ]
            }
          }
        }
      }
      JSON

    rows = endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.sort!
    rows.should eq(["GET /stations", "PUT /document", "PUT /pet", "SUBSCRIBE /trips/{id}"])

    subscribe = endpoints.find { |endpoint| endpoint.method == "SUBSCRIBE" }
    subscribe.should_not be_nil
    if subscribe
      json_names(subscribe, "query").should eq(["verbose"])
    end
    document = endpoints.find { |endpoint| endpoint.url == "/document" }
    document.should_not be_nil
    if document
      json_names(document, "json").should eq(["docType", "headline"])
    end
    pet = endpoints.find { |endpoint| endpoint.url == "/pet" }
    pet.should_not be_nil
    if pet
      json_names(pet, "json").should eq(["huntingSkill", "petType"])
    end
  end
end
