require "../../spec_helper"
require "file_utils"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/elixir/elixir_phoenix"
require "../../../src/cli/inspect"

private def scan_phoenix(files : Hash(String, String)) : Array(Endpoint)
  temp_dir = File.tempname("phoenix_forward")
  CodeLocator.instance.clear_all
  files.each do |name, content|
    path = File.join(temp_dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  Analyzer::Elixir::Phoenix.new(options).analyze
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "Phoenix forward and scope root" do
  it "traces an external forward as ANY on the prefix and its subpaths" do
    endpoints = scan_phoenix({
      "lib/app_web/router.ex" => <<-ELIXIR,
        defmodule AppWeb.Router do
          use AppWeb, :router

          get "/health", HealthController, :show
          forward "/sent-emails", Bamboo.SentEmailViewerPlug
        end
        ELIXIR
    })

    forward = endpoints.find(&.url.includes?("sent-emails"))
    forward.should_not be_nil
    if forward
      forward.method.should eq("ANY")
      Noir::CLI::Inspect.trace(endpoints, "POST", "/sent-emails").map(&.endpoint.url).should eq([forward.url])
      Noir::CLI::Inspect.trace(endpoints, "GET", "/sent-emails/42").map(&.endpoint.url).should eq([forward.url])
    end
    Noir::CLI::Inspect.trace(endpoints, "POST", "/health").should be_empty
    Noir::CLI::Inspect.trace(endpoints, "GET", "/health").map(&.endpoint.url).should eq(["/health"])
  end

  it "does not emit an ANY forward for an in-tree Plug.Router" do
    endpoints = scan_phoenix({
      "lib/app_web/router.ex" => <<-ELIXIR,
        defmodule AppWeb.Router do
          use AppWeb, :router

          scope "/api", AppWeb do
            forward "/users", Users.Plug
          end
        end
        ELIXIR
      "lib/app_web/users_plug.ex" => <<-ELIXIR,
        defmodule AppWeb.Users.Plug do
          use Plug.Router
          plug :match
          plug :dispatch

          get "/list" do
            send_resp(conn, 200, "")
          end
        end
        ELIXIR
    })

    endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.should eq([] of String)
  end

  it "drops the trailing slash when the route inside a scope is /" do
    endpoints = scan_phoenix({
      "lib/app_web/router.ex" => <<-ELIXIR,
        defmodule AppWeb.Router do
          use AppWeb, :router

          scope "/api/v1/sites", AppWeb do
            get "/", SiteController, :index
            post "/", SiteController, :create
            get "/:id", SiteController, :show
          end

          get "/", PageController, :home
        end
        ELIXIR
    })

    endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.sort!.should eq([
      "GET /",
      "GET /api/v1/sites",
      "GET /api/v1/sites/:id",
      "POST /api/v1/sites",
    ])
  end
end
