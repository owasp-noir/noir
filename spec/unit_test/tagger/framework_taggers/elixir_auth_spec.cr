require "../../../spec_helper"
require "../../../../src/tagger/tagger"
require "file_utils"

describe "ElixirAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/elixir/phoenix_auth", __DIR__)
  controller_path = "#{fixture_base}/lib/myapp_web/controllers/post_controller.ex"
  public_path = "#{fixture_base}/lib/myapp_web/controllers/public_controller.ex"

  # post_controller.ex line reference:
  #  3: plug :require_authenticated_user
  #  5: def index(conn, _params) do
  # 10: def show(conn, %{"id" => id}) do

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects plug :require_authenticated_user" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(controller_path, 5))
    details.technology = "elixir_phoenix"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = ElixirAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("elixir_auth")
    endpoint.tags[0].description.should contain("require_authenticated_user")
  end

  it "reads a pipe_through list wrapped over lines" do
    dir = File.tempname("noir_elixir_auth")
    Dir.mkdir_p(dir)
    router = File.join(dir, "router.ex")
    File.write(router, <<-EX)
      defmodule AppWeb.Router do
        scope "/wrapped", AppWeb do
          pipe_through [
            :browser,
            :auth
          ]
          get "/b", PageController, :b
        end

        scope "/open", AppWeb do
          pipe_through [
            :browser
            # :auth
          ]
          get "/c", PageController, :c
        end
      end
      EX

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      CodeLocator.instance.register_path(router)

      wrapped = Endpoint.new("/wrapped/b", "GET", [] of Param, Details.new(PathInfo.new(router, 7)))
      open = Endpoint.new("/open/c", "GET", [] of Param, Details.new(PathInfo.new(router, 15)))

      ElixirAuthTagger.new(noir_options).perform([wrapped, open])

      wrapped.tags.map(&.description).should eq(["Protected by Phoenix :auth pipeline"])
      open.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "tags only the phx.gen.auth blocks that require a user" do
    dir = File.tempname("noir_elixir_auth")
    Dir.mkdir_p(dir)
    router = File.join(dir, "router.ex")
    File.write(router, <<-EX)
      defmodule AppWeb.Router do
        use AppWeb, :router
        import AppWeb.UserAuth

        pipeline :browser do
          plug :fetch_session
          plug :fetch_current_user
        end

        pipeline :api_protected do
          plug Guardian.Plug.EnsureAuthenticated
        end

        scope "/", AppWeb do
          pipe_through :browser
          get "/", PageController, :home
        end

        scope "/", AppWeb do
          pipe_through [:browser, :redirect_if_user_is_authenticated]
          get "/users/log_in", UserSessionController, :new
        end

        scope "/", AppWeb do
          pipe_through [:browser, :require_authenticated_user]
          get "/users/settings", UserSettingsController, :edit
        end

        scope "/", AppWeb do
          pipe_through :browser

          live_session :require_authenticated_user,
            on_mount: [{AppWeb.UserAuth, :ensure_authenticated}] do
            live "/users/profile", ProfileLive, :edit
          end

          live_session :current_user,
            on_mount: [{AppWeb.UserAuth, :mount_current_user}] do
            live "/users/confirm", ConfirmLive, :new
          end
        end

        scope "/api", AppWeb do
          pipe_through :api_protected
          get "/me", ApiController, :me
        end
      end
      EX

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      CodeLocator.instance.register_path(router)

      at = ->(url : String, line : Int32) { Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(router, line))) }
      home = at.call("/", 16)
      log_in = at.call("/users/log_in", 21)
      settings = at.call("/users/settings", 26)
      profile = at.call("/users/profile", 34)
      confirm = at.call("/users/confirm", 39)
      me = at.call("/api/me", 45)

      ElixirAuthTagger.new(noir_options).perform([home, log_in, settings, profile, confirm, me])

      home.tags.should be_empty
      log_in.tags.should be_empty
      confirm.tags.should be_empty
      settings.tags.map(&.description).should eq(["Protected by Phoenix :require_authenticated_user pipeline"])
      profile.tags.map(&.description).should eq(["Protected by Phoenix live_session :ensure_authenticated on_mount"])
      me.tags.map(&.description).should eq(["Protected by Phoenix :api_protected pipeline"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "does not tag public controller" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.register_path(file)
    end

    details = Details.new(PathInfo.new(public_path, 4))
    details.technology = "elixir_phoenix"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = ElixirAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "judges a multi-clause plug by every clause, including a Router.Helpers login redirect" do
    dir = File.tempname("noir_elixir_clauses")
    Dir.mkdir_p(dir)
    plug = File.join(dir, "require_user.ex")
    controller = File.join(dir, "post_controller.ex")
    File.write(plug, <<-EX)
      defmodule AppWeb.Plug.RequireUser do
        import Plug.Conn
        alias AppWeb.Router.Helpers

        def init(opts), do: opts

        def call(conn = %{assigns: %{current_user: user}}, _opts) when not is_nil(user), do: conn
        def call(conn, _opts) do
          conn
          |> redirect(to: Helpers.sign_in_path(conn, :new))
          |> halt()
        end
      end
      EX
    File.write(controller, <<-EX)
      defmodule AppWeb.PostController do
        use AppWeb, :controller
        alias AppWeb.Plug.RequireUser

        plug RequireUser when action in [:create]

        def create(conn, params), do: render(conn, :show, post: params)

        def show(conn, %{"id" => id}), do: render(conn, :show, id: id)
      end
      EX

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      CodeLocator.instance.register_path(plug)
      CodeLocator.instance.register_path(controller)

      create = Endpoint.new("/posts", "POST", [] of Param, Details.new(PathInfo.new(controller, 7)))
      show = Endpoint.new("/posts/:id", "GET", [] of Param, Details.new(PathInfo.new(controller, 9)))
      ElixirAuthTagger.new(noir_options).perform([create, show])

      create.tags.map(&.description).should eq(["Protected by Phoenix RequireUser plug"])
      show.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "judges plugs imported or aliased by `use AppWeb, :controller`" do
    dir = File.tempname("noir_elixir_use_imports")
    Dir.mkdir_p(dir)
    web = File.join(dir, "app_web.ex")
    helpers = File.join(dir, "controller_helpers.ex")
    admin_plug = File.join(dir, "require_admin.ex")
    controller = File.join(dir, "dashboard_controller.ex")
    File.write(web, <<-EX)
      defmodule AppWeb do
        def controller do
          quote do
            use Phoenix.Controller
            import AppWeb.{ControllerHelpers, Gettext}
            alias AppWeb.Plug.{RequireAdmin}
          end
        end
      end
      EX
    File.write(admin_plug, <<-EX)
      defmodule AppWeb.Plug.RequireAdmin do
        def init(opts), do: opts

        def call(conn, _opts) do
          if conn.assigns.current_user.admin, do: conn, else: conn |> send_resp(403, "") |> halt()
        end
      end
      EX
    File.write(helpers, <<-EX)
      defmodule AppWeb.ControllerHelpers do
        def requires_login(conn, _opts) do
          if logged_in?(conn) do
            conn
          else
            conn |> redirect(to: ~p"/login") |> halt()
          end
        end

        def assign_theme(conn, _opts), do: assign(conn, :theme, "dark")

        def logged_in?(conn), do: !!conn.assigns[:current_user]
      end
      EX
    File.write(controller, <<-EX)
      defmodule AppWeb.DashboardController do
        use AppWeb, :controller

        plug :requires_login when action in [:index]
        plug RequireAdmin when action in [:settings]
        plug :assign_theme

        def index(conn, _params), do: render(conn, :index)

        def about(conn, _params), do: render(conn, :about)

        def settings(conn, _params), do: render(conn, :settings)
      end
      EX

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      [web, helpers, admin_plug, controller].each { |file| CodeLocator.instance.register_path(file) }

      index = Endpoint.new("/dashboard", "GET", [] of Param, Details.new(PathInfo.new(controller, 8)))
      about = Endpoint.new("/about", "GET", [] of Param, Details.new(PathInfo.new(controller, 10)))
      settings = Endpoint.new("/settings", "GET", [] of Param, Details.new(PathInfo.new(controller, 12)))
      ElixirAuthTagger.new(noir_options).perform([index, about, settings])

      index.tags.map(&.description).should eq(["Protected by Phoenix :requires_login plug"])
      settings.tags.map(&.description).should eq(["Protected by Phoenix RequireAdmin plug"])
      about.tags.should be_empty
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "counts only enforcing plugs when deciding a pipeline is an auth pipeline" do
    dir = File.tempname("noir_elixir_pipeline_plugs")
    Dir.mkdir_p(dir)
    router = File.join(dir, "router.ex")
    File.write(router, <<-EX)
      defmodule AppWeb.Router do
        use AppWeb, :router

        pipeline :maybe_user do
          plug Guardian.Plug.VerifyHeader, realm: "Bearer"
          plug Guardian.Plug.LoadResource, allow_blank: true
        end

        pipeline :oauth do
          plug Ueberauth
        end

        pipeline :api_secure do
          plug Guardian.Plug.VerifyHeader
          plug Guardian.Plug.EnsureAuthenticated
        end

        pipeline :members do
          plug :require_logged_in_user
        end

        scope "/", AppWeb do
          pipe_through :maybe_user
          get "/posts", PostController, :index
        end

        scope "/auth", AppWeb do
          pipe_through :oauth
          get "/:provider", AuthController, :request
        end

        scope "/api", AppWeb do
          pipe_through :api_secure
          get "/me", ApiController, :me
        end

        scope "/members", AppWeb do
          pipe_through :members
          get "/", MemberController, :index
        end
      end
      EX

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(dir)
      CodeLocator.instance.register_path(router)

      at = ->(url : String, line : Int32) { Endpoint.new(url, "GET", [] of Param, Details.new(PathInfo.new(router, line))) }
      posts = at.call("/posts", 24)
      provider = at.call("/auth/:provider", 29)
      me = at.call("/api/me", 34)
      members = at.call("/members", 39)

      ElixirAuthTagger.new(noir_options).perform([posts, provider, me, members])

      posts.tags.should be_empty
      provider.tags.should be_empty
      me.tags.map(&.description).should eq(["Protected by Phoenix :api_secure pipeline"])
      members.tags.map(&.description).should eq(["Protected by Phoenix :members pipeline"])
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
