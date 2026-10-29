require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/asyncapi"

private def analyze_asyncapi(content : String, key, ext : String)
  path = File.tempname("asyncapi", ext)
  File.write(path, content)
  locator = CodeLocator.instance
  locator.clear key
  locator.push key, path

  Analyzer::Specification::AsyncApi.new(create_test_options).analyze
ensure
  CodeLocator.instance.clear key
  File.delete(path) if path && File.exists?(path)
end

private ONE_OF_YAML = <<-YAML
  asyncapi: 2.6.0
  info: {title: t, version: 1.0.0}
  channels:
    light/measured:
      subscribe:
        message:
          oneOf:
            - $ref: '#/components/messages/lightMeasured'
            - $ref: '#/components/messages/lightOff'
  components:
    messages:
      lightMeasured:
        payload:
          type: object
          properties:
            lumens: {type: integer}
            sentAt: {type: string}
      lightOff:
        payload:
          type: object
          properties:
            reason: {type: string}
            sentAt: {type: string}
  YAML

describe "AsyncAPI Analyzer" do
  it "collects payload params from every message of a 2.x oneOf (YAML)" do
    endpoints = analyze_asyncapi(ONE_OF_YAML, Noir::LocatorKeys::ASYNCAPI_YAML, ".yaml")
    endpoints.size.should eq(1)
    endpoints[0].params.map(&.name).should eq(["lumens", "sentAt", "reason"])
  end

  it "falls back to channel messages and unwraps a multi-format schema (JSON)" do
    json = <<-JSON
      {
        "asyncapi": "3.0.0",
        "info": {"title": "t", "version": "1.0.0"},
        "channels": {
          "rooms": {
            "address": "/rooms/{roomId}",
            "messages": {
              "chat": {"$ref": "#/components/messages/chat"}
            },
            "bindings": {
              "ws": {"query": {"type": "object", "properties": {"heartbeat": {"type": "boolean"}}}}
            }
          }
        },
        "operations": {
          "sendRoom": {"action": "send", "channel": {"$ref": "#/channels/rooms"}}
        },
        "components": {
          "messages": {
            "chat": {
              "payload": {
                "schemaFormat": "application/schema+json;version=draft-07",
                "schema": {"type": "object", "properties": {"text": {"type": "string"}}}
              }
            }
          }
        }
      }
      JSON

    endpoints = analyze_asyncapi(json, Noir::LocatorKeys::ASYNCAPI_JSON, ".json")
    endpoints.size.should eq(1)
    endpoints[0].params.map { |param| {param.name, param.param_type} }.sort!.should eq([
      {"heartbeat", "query"},
      {"text", "json"},
    ])
  end

  it "collects payload params from every message of a 2.x oneOf (JSON)" do
    json = YAML.parse(ONE_OF_YAML).to_json
    endpoints = analyze_asyncapi(json, Noir::LocatorKeys::ASYNCAPI_JSON, ".json")
    endpoints.size.should eq(1)
    endpoints[0].params.map(&.name).should eq(["lumens", "sentAt", "reason"])
  end
end
