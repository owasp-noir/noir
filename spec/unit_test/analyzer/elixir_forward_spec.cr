require "../../spec_helper"
require "file_utils"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/elixir/elixir_plug"
require "../../../src/analyzer/analyzers/elixir/elixir_phoenix"

private def scan_elixir_forward_app(files : Hash(String, String), & : Hash(String, YAML::Any) -> Array(Endpoint)) : Array(String)
  temp_dir = File.tempname("elixir_forward_test")
  CodeLocator.instance.clear_all
  files.each do |name, content|
    path = File.join(temp_dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
  yield(options).map { |e| "#{e.method} #{e.url}" }.sort!
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

USERS_ROUTER = <<-ELIXIR
  defmodule MyApp.UsersRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    get "/:id" do
      send_resp(conn, 200, id)
    end

    forward "/admin", to: MyApp.AdminRouter
  end
  ELIXIR

ADMIN_ROUTER = <<-ELIXIR
  defmodule MyApp.AdminRouter do
    use Plug.Router
    plug :match
    plug :dispatch

    delete "/purge" do
      send_resp(conn, 204, "")
    end
  end
  ELIXIR

describe "Elixir forward mounts" do
  it "re-roots a Plug.Router child under its forward path, through nested forwards" do
    routes = scan_elixir_forward_app({
      "lib/router.ex" => <<-ELIXIR,
        defmodule MyApp.Router do
          use Plug.Router
          plug :match
          plug :dispatch

          get "/hello" do
            send_resp(conn, 200, "world")
          end

          forward "/users", to: MyApp.UsersRouter
          forward "/graphql", to: Absinthe.Plug
        end
        ELIXIR
      "lib/users_router.ex" => USERS_ROUTER,
      "lib/admin_router.ex" => ADMIN_ROUTER,
    }) { |options| Analyzer::Elixir::Plug.new(options).analyze }

    routes.should eq(["DELETE /users/admin/purge", "FORWARD /graphql", "GET /hello", "GET /users/:id"])
  end

  it "re-roots a child of a Phoenix router forward inside a scope and drops the forward" do
    files = {
      "lib/app_web/router.ex" => <<-ELIXIR,
        defmodule AppWeb.Router do
          use AppWeb, :router

          scope "/api", AppWeb do
            get "/status", StatusController, :show
            forward "/users", Users.Plug
          end

          forward "/mailbox", Plug.Swoosh.MailboxPreview
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
    }

    scan_elixir_forward_app(files) { |options| Analyzer::Elixir::Plug.new(options).analyze }
      .should eq(["GET /api/users/list"])
    scan_elixir_forward_app(files) { |options| Analyzer::Elixir::Phoenix.new(options).analyze }
      .should eq(["ANY /mailbox{/*path}", "GET /api/status"])
  end
end
