require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"
require "../../../../src/models/code_locator"

describe "Detect Bruno Collection" do
  options = create_test_options
  instance = Detector::Specification::Bruno.new options

  it "detects a request file with a method block" do
    content = <<-BRU
      meta {
        name: List Users
        type: http
      }

      get {
        url: https://api.example.com/users
      }
      BRU

    instance.detect("list-users.bru", content).should be_true
  end

  it "ignores non-.bru filenames" do
    content = <<-BRU
      get {
        url: https://api.example.com/users
      }
      BRU

    instance.detect("list-users.txt", content).should be_false
  end

  it "ignores .bru files without a recognized block header" do
    content = <<-BRU
      # not a real .bru file
      hello world
      BRU

    instance.detect("notes.bru", content).should be_false
  end

  it "registers the path in the code locator" do
    content = <<-BRU
      get {
        url: https://api.example.com/health
      }
      BRU

    locator = CodeLocator.instance
    locator.clear "bruno-bru"
    instance.detect("health.bru", content)
    locator.all("bruno-bru").should eq(["health.bru"])
  end
end
