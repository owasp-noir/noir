require "../../spec_helper"
require "../../../src/utils/*"
require "../../../src/models/endpoint.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/tagger.cr"
require "yaml"

describe "Tagger" do
  describe "initialization" do
    it "creates tagger with options" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
      }
      tagger = Tagger.new(options)

      tagger.should_not be_nil
      tagger.name.should eq("")
    end

    it "initializes with debug option" do
      options = {
        "debug"   => YAML::Any.new(true),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
      }
      tagger = Tagger.new(options)

      tagger.should_not be_nil
    end
  end

  describe "name" do
    it "returns empty string by default" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
      }
      tagger = Tagger.new(options)

      tagger.name.should eq("")
    end
  end

  describe "perform" do
    it "returns endpoints unchanged in base implementation" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
      }
      tagger = Tagger.new(options)

      endpoint1 = Endpoint.new("/api/users", "GET")
      endpoint2 = Endpoint.new("/api/posts", "POST")
      endpoints = [endpoint1, endpoint2]

      result = tagger.perform(endpoints)

      result.size.should eq(2)
      result[0].url.should eq("/api/users")
      result[1].url.should eq("/api/posts")
    end

    it "handles empty endpoint array" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
      }
      tagger = Tagger.new(options)

      result = tagger.perform([] of Endpoint)

      result.should be_empty
    end
  end
end
