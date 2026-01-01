require "../../spec_helper"
require "../../../src/output_builder/diff"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

describe "OutputBuilderDiff" do
  describe "diff" do
    it "correctly identifies added endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/api/users", "POST"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      result[:added].size.should eq(1)
      result[:added][0].url.should eq("/api/users")
      result[:added][0].method.should eq("POST")
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end

    it "correctly identifies removed endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/api/users", "POST"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      result[:added].size.should eq(0)
      result[:removed].size.should eq(1)
      result[:removed][0].url.should eq("/api/users")
      result[:removed][0].method.should eq("POST")
      result[:changed].size.should eq(0)
    end

    it "correctly identifies changed endpoints" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoint = Endpoint.new("/test", "GET")
      new_endpoint.push_param(Param.new("id", "1", "query"))

      old_endpoint = Endpoint.new("/test", "GET")
      # No params in old endpoint

      result = builder.diff([new_endpoint], [old_endpoint])

      result[:added].size.should eq(0)
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(1)
      result[:changed][0].url.should eq("/test")
    end

    it "handles empty endpoint arrays" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      result = builder.diff([] of Endpoint, [] of Endpoint)

      result[:added].size.should eq(0)
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end

    it "matches endpoints by url and method combination" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderDiff.new(options)

      new_endpoints = [
        Endpoint.new("/test", "GET"),
        Endpoint.new("/test", "POST"),
      ]
      old_endpoints = [
        Endpoint.new("/test", "GET"),
      ]

      result = builder.diff(new_endpoints, old_endpoints)

      # POST /test should be added, GET /test should be unchanged
      result[:added].size.should eq(1)
      result[:added][0].method.should eq("POST")
      result[:removed].size.should eq(0)
      result[:changed].size.should eq(0)
    end
  end
end
