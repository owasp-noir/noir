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
end
