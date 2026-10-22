require "../../spec_helper"
require "file_utils"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/elixir/elixir_phoenix"

private def phoenix_routes(files : Hash(String, String)) : Hash(String, Array(String))
  temp_dir = File.tempname("phoenix_params_test")
  CodeLocator.instance.clear_all
  files.each do |name, content|
    path = File.join(temp_dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  Analyzer::Elixir::Phoenix.new(options).analyze.to_h do |e|
    {"#{e.method} #{e.url}", e.params.map { |p| "#{p.name}:#{p.param_type}" }.sort!}
  end
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "Phoenix action params" do
  it "reads head map patterns and the bound params variable, and skips trailing comments on route lines" do
    routes = phoenix_routes({
      "lib/app_web/router.ex" => <<-ELIXIR,
        defmodule AppWeb.Router do
          use AppWeb, :router

          scope "/", AppWeb do
            get "/users", UserController, :index
            post "/users", UserController, :create # get "/trailing", UserController, :index
            put "/users/:id", UserController, :update
            post "/hooks/:provider", UserController, :hook
          end
        end
        ELIXIR
      "lib/app_web/controllers/user_controller.ex" => <<-ELIXIR,
        defmodule AppWeb.UserController do
          use AppWeb, :controller

          def index(conn, params) do
            page = Map.get(params, "page", "1")
            render(conn, :index, q: params["q"])
          end

          def create(conn, %{"user" => user_params}) do
            render(conn, :new, user: user_params)
          end

          def update(conn, %{"id" => id, "user" => %{"email" => email}}) do
            render(conn, :show, id: id, email: email)
          end

          def hook(conn, %{"provider" => provider} = params) do
            json(conn, %{provider: provider, event: params["event"]})
          end
        end
        ELIXIR
    })

    routes.keys.sort!.should eq(["GET /users", "POST /hooks/:provider", "POST /users", "PUT /users/:id"])
    routes["GET /users"].should eq(["page:query", "q:query"])
    routes["POST /users"].should eq(["user:form"])
    routes["PUT /users/:id"].should eq(["user:form"])
    routes["POST /hooks/:provider"].should eq(["event:form"])
  end
end
