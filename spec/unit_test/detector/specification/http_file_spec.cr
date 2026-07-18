require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect HTTP/REST Client Files" do
  options = create_test_options
  instance = Detector::Specification::HttpFile.new options

  it "detects a .http file with a request line" do
    content = <<-HTTP
      ### Get a user
      GET https://api.example.com/users/{{userId}}
      Authorization: Bearer token
      HTTP

    instance.detect("api.http", content).should be_true
  end

  it "detects a method-less .rest request as GET" do
    content = <<-HTTP
      GET https://api.example.com/ping
      HTTP

    instance.detect("ping.rest", content).should be_true
  end

  it "ignores non-.http/.rest filenames" do
    content = "GET https://api.example.com/users\n"
    instance.detect("requests.txt", content).should be_false
  end

  it "ignores a .rest file that is actually reStructuredText" do
    content = <<-RST
      Title
      =====

      Some prose without an HTTP request line.
      RST

    instance.detect("readme.rest", content).should be_false
  end

  it "ignores verb-initial prose without a URL-ish target" do
    content = <<-RST
      Get started with the API.
      Delete the old files first.
      Post the form to submit.
      RST

    instance.detect("guide.rest", content).should be_false
  end

  it "registers the path in the code locator" do
    content = "POST https://api.example.com/orders\n"

    locator = CodeLocator.instance
    locator.clear "http-file"
    instance.detect("orders.http", content)
    locator.all("http-file").should eq(["orders.http"])
  end
end
