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

  it "detects a file whose only request uses the QUERY verb" do
    content = <<-HTTP
      QUERY https://api.example.com/products/search
      Content-Type: application/x-www-form-urlencoded

      q=widget
      HTTP

    instance.detect("search.http", content).should be_true
  end

  it "ignores 'Query <url-ish>' prose — QUERY only counts in uppercase" do
    # Unlike "Get started with the API", prose idiomatically puts a URL-ish
    # token right after "Query", so the case-lenient match that is safe for
    # the classic verbs would fabricate request files out of documentation.
    prose = <<-RST
      Query /users for the list of accounts.
      Query api.example.com/v1/search when you need full-text results.
      Query https://api.example.com/search to list products.
      RST

    instance.detect("guide.rest", prose).should be_false
    instance.detect("lower.http", "query /products/search\n").should be_false
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
    locator.clear Noir::LocatorKeys::HTTP_FILE
    instance.detect("orders.http", content)
    locator.all(Noir::LocatorKeys::HTTP_FILE).should eq(["orders.http"])
  end
end
