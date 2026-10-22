require "../../../spec_helper"
require "../../../../src/models/code_locator"
require "../../../../src/analyzer/analyzers/specification/har"

private def analyze_har(content : String) : Array(Endpoint)
  path = File.tempname("noir_har_", ".har")
  File.write(path, content)
  CodeLocator.instance.clear Noir::LocatorKeys::HAR_PATH
  CodeLocator.instance.push Noir::LocatorKeys::HAR_PATH, path
  Analyzer::Specification::Har.new(create_test_options).analyze
ensure
  CodeLocator.instance.clear Noir::LocatorKeys::HAR_PATH
  File.delete(path) if path && File.exists?(path)
end

private def har_entry(method : String, url : String, body_size : String) : String
  <<-JSON
    {"startedDateTime": "2024-01-01T00:00:00.000Z", "time": 1,
      "request": {"method": "#{method}", "url": "#{url}", "httpVersion": "HTTP/1.1",
        "cookies": [], "headers": [], "queryString": [], "headersSize": -1, "bodySize": #{body_size}},
      "response": {"status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1", "cookies": [], "headers": [],
        "content": {"size": #{body_size}, "mimeType": "application/json"}, "redirectURL": "",
        "headersSize": -1, "bodySize": #{body_size}},
      "cache": {}, "timings": {"send": 0, "wait": 0, "receive": 0}}
    JSON
end

private def har_log(*entries : String) : String
  %({"log": {"version": "1.2", "creator": {"name": "x", "version": "1"}, "entries": [#{entries.join(", ")}]}})
end

describe "HAR Analyzer" do
  it "keeps entries whose sizes do not fit in Int32" do
    endpoints = analyze_har(har_log(
      har_entry("GET", "https://h.example/a", "3000000000"),
      har_entry("POST", "https://h.example/b", "99999999999999999999"),
    ))
    endpoints.map { |e| "#{e.method} #{e.url}" }.should eq ["GET https://h.example/a", "POST https://h.example/b"]
  end

  it "reads a BOM-prefixed archive" do
    endpoints = analyze_har("﻿" + har_log(har_entry("GET", "https://h.example/bom", "0")))
    endpoints.map(&.url).should eq ["https://h.example/bom"]
  end
end
