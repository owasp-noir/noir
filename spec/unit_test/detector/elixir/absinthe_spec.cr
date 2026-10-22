require "../../../spec_helper"
require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Absinthe" do
  options = create_test_options
  instance = Detector::Elixir::Absinthe.new options

  it "detects a schema module" do
    schema = <<-EX
      defmodule BlogWeb.Schema do
        use Absinthe.Schema
        query do
        end
      end
      EX
    instance.detect("lib/blog_web/schema.ex", schema).should be_true
  end

  it "detects a type module" do
    types = <<-EX
      defmodule BlogWeb.Schema.ContentTypes do
        use Absinthe.Schema.Notation
      end
      EX
    instance.detect("lib/blog_web/schema/content_types.ex", types).should be_true
  end

  it "ignores a mention outside a use line" do
    router = <<-EX
      defmodule BlogWeb.Router do
        # Mounts the schema built with `use Absinthe.Schema`.
        forward "/api", Absinthe.Plug, schema: BlogWeb.Schema
      end
      EX
    instance.detect("lib/blog_web/router.ex", router).should be_false
  end
end
