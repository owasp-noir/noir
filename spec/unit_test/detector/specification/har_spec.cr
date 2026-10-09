require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"
require "../../../../src/models/skipped_files"

private def scan_failures : Array(String)
  Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan).map(&.message)
end

describe "Detect HAR" do
  options = create_test_options
  instance = Detector::Specification::Har.new options

  har = <<-JSON
    {"log": {"version": "1.2", "creator": {"name": "t", "version": "1"},
     "entries": [{"startedDateTime": "2024-01-01T00:00:00Z", "time": 1,
       "request": {"method": "GET", "url": "http://h/a", "httpVersion": "HTTP/1.1",
         "cookies": [], "headers": [], "queryString": [], "headersSize": -1, "bodySize": 0},
       "response": {"status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1",
         "cookies": [], "headers": [], "content": {"size": 0, "mimeType": "text/plain"},
         "redirectURL": "", "headersSize": -1, "bodySize": 0},
       "cache": {}, "timings": {"send": 0, "wait": 0, "receive": 0}}]}}
    JSON

  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  it "detects a HAR capture saved as .json" do
    locator = CodeLocator.instance
    locator.clear Noir::LocatorKeys::HAR_PATH

    instance.detect("capture.json", har).should be_true
    locator.all(Noir::LocatorKeys::HAR_PATH).should eq ["capture.json"]
  end

  # Matching the bare key names claimed this locale file, then reported it
  # as an unparsable HAR, so `--strict` failed a scan with no HAR in it.
  it "ignores JSON that only mentions log and entries" do
    instance.detect("locale.json", %({"log":"Log","entries":"Entries"})).should be_false
    scan_failures.should be_empty
  end

  it "still records a truncated HAR-shaped .json" do
    instance.detect("capture.json", har[0, 120]).should be_false
    scan_failures.join.should contain("capture.json")
  end

  it "records any .har that does not parse" do
    instance.detect("broken.har", %({"log":"Log"})).should be_false
    scan_failures.join.should contain("broken.har")
  end
end
