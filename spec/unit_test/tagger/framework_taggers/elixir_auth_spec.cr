require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "ElixirAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/elixir/phoenix_auth"
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
      locator.push("file_map", file)
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

  it "does not tag public controller" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(public_path, 4))
    details.technology = "elixir_phoenix"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = ElixirAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
