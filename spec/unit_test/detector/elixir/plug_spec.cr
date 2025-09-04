require "../../../spec_helper"
require "../../../../src/detector/detectors/elixir/*"

describe "Detect Elixir Plug" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Elixir::Plug.new options

  it "detects Plug in mix.exs with {:plug, dependency" do
    mix_content = <<-MIX
    defmodule MyApp.MixProject do
      use Mix.Project

      def project do
        [
          app: :my_app,
          version: "0.1.0",
          elixir: "~> 1.12",
          deps: deps()
        ]
      end

      defp deps do
        [
          {:plug, "~> 1.14"},
          {:plug_cowboy, "~> 2.5"}
        ]
      end
    end
    MIX

    instance.detect("mix.exs", mix_content).should eq(true)
  end

  it "detects Plug in mix.exs with plug: dependency" do
    mix_content = <<-MIX
    defmodule MyApp.MixProject do
      use Mix.Project

      defp deps do
        [
          plug: "~> 1.14"
        ]
      end
    end
    MIX

    instance.detect("mix.exs", mix_content).should eq(true)
  end

  it "detects Plug Router in Elixir file" do
    router_content = <<-ELIXIR
    defmodule MyApp.Router do
      use Plug.Router

      plug :match
      plug :dispatch

      get "/hello" do
        send_resp(conn, 200, "Hello World!")
      end

      match _ do
        send_resp(conn, 404, "Not found")
      end
    end
    ELIXIR

    instance.detect("lib/router.ex", router_content).should eq(true)
  end

  it "detects Plug import in Elixir file" do
    plug_content = <<-ELIXIR
    defmodule MyApp.Handler do
      import Plug.Conn

      def call(conn, _opts) do
        send_resp(conn, 200, "OK")
      end
    end
    ELIXIR

    instance.detect("lib/handler.ex", plug_content).should eq(true)
  end

  it "detects forward statements in Elixir file" do
    router_content = <<-ELIXIR
    defmodule MyApp.Router do
      use Plug.Router

      forward "/api", to: MyApp.API
      
      get "/health", do: send_resp(conn, 200, "OK")
    end
    ELIXIR

    instance.detect("lib/router.ex", router_content).should eq(true)
  end

  it "does not detect non-Plug files" do
    non_plug_content = <<-ELIXIR
    defmodule MyApp.Utils do
      def hello do
        "Hello World"
      end
    end
    ELIXIR

    instance.detect("lib/utils.ex", non_plug_content).should eq(false)
  end

  it "does not detect non-mix.exs files without Plug patterns" do
    instance.detect("mix.exs", "# Just a comment").should eq(false)
  end
end