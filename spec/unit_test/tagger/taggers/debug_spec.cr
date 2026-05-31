require "../../../spec_helper"
require "../../../../src/utils/*"
require "../../../../src/models/endpoint.cr"
require "../../../../src/models/logger.cr"
require "../../../../src/models/tagger.cr"
require "../../../../src/tagger/taggers/debug.cr"
require "yaml"

def default_tagger_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

describe "DebugTagger" do
  describe "initialization" do
    it "creates tagger with name" do
      tagger = DebugTagger.new(default_tagger_options)
      tagger.name.should eq("debug")
    end
  end

  describe "perform" do
    it "tags a Spring Boot Actuator endpoint" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/actuator/env", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags a Go pprof endpoint" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/debug/pprof/heap", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags a phpinfo endpoint" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/phpinfo.php", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags an internal API path" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/internal/users", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags a Laravel Telescope endpoint" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/telescope/requests", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "does not tag compound business names containing 'internal'" do
      tagger = DebugTagger.new(default_tagger_options)

      transfer = Endpoint.new("/accounts/internal-transfer", "POST")
      notes = Endpoint.new("/crm/internal-notes/42", "GET")

      tagger.perform([transfer, notes])

      transfer.tags.size.should eq(0)
      notes.tags.size.should eq(0)
    end

    it "tags a Werkzeug interactive debugger console parameter" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/console", "GET", [
        Param.new("__debugger__", "yes", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags a debug toggle parameter regardless of path" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/report", "GET", [
        Param.new("debug", "true", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "tags when two distinct weak diagnostic tokens co-occur" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/monitoring/metrics", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(1)
      endpoint.tags[0].name.should eq("debug")
    end

    it "does not tag on a single weak diagnostic token" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/metrics", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not tag a benign endpoint" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/products", "GET", [
        Param.new("page", "1", "query"),
      ])

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end

    it "does not match a substring (e.g. debugger word boundaries)" do
      tagger = DebugTagger.new(default_tagger_options)

      endpoint = Endpoint.new("/api/internalized/notes", "GET")

      tagger.perform([endpoint])

      endpoint.tags.size.should eq(0)
    end
  end
end
