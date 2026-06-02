require "../../../spec_helper"
require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Phoenix" do
  options = create_test_options
  instance = Detector::Elixir::Phoenix.new options

  it "detects the core phoenix dependency in mix.exs" do
    mix = <<-MIX
      defp deps do
        [
          {:phoenix, "~> 1.7.1"},
          {:phoenix_ecto, "~> 4.4"},
          {:plug_cowboy, "~> 2.5"}
        ]
      end
      MIX
    instance.detect("mix.exs", mix).should be_true
  end

  it "does not match sibling phoenix_* deps alone" do
    mix = <<-MIX
      defp deps do
        [
          {:phoenix_html, "~> 3.3"},
          {:phoenix_live_view, "~> 0.18"}
        ]
      end
      MIX
    instance.detect("mix.exs", mix).should be_false
  end

  it "detects a router via the `use _, :router` convention" do
    router = <<-EX
      defmodule MyAppWeb.Router do
        use MyAppWeb, :router

        scope "/", MyAppWeb do
          get "/", PageController, :index
        end
      end
      EX
    instance.detect("lib/my_app_web/router.ex", router).should be_true
  end

  it "detects a router that uses Phoenix.Router directly" do
    router = <<-EX
      defmodule MyAppWeb.Router do
        use Phoenix.Router
      end
      EX
    instance.detect("lib/my_app_web/router.ex", router).should be_true
  end

  it "ignores unrelated elixir files" do
    instance.detect("lib/my_app/foo.ex", "defmodule Foo do\nend\n").should be_false
  end
end
