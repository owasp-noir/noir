require "../../func_spec.cr"

describe "--ai-context on flask-restx auth fixtures", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "judges Resource method and class decorators by their definitions" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_restx_auth/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guards = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.guards.map(&.name)) || [] of String}
    end

    # login-manager answer, a 401 one call down through method_decorators
    # inherited from a base class, a composite returning another guard, and
    # a request key compared before a 404.
    guards["GET /v1/profile"].should eq(["session_required"])
    guards["GET /v1/items/<int:item_id>"].should eq(["token_required"])
    guards["PUT /v1/settings"].should eq(["admission"])
    guards["POST /v1/inner/sync"].should eq(["inner_key_only"])
    # A feature-flag 403 and a local no-op named `login_required` guard
    # nothing: the tagger reads both definitions. (The route-source scan
    # still name-matches `login_required` near the route, at low confidence.)
    signup = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/v1/signup" }
    signup.tags.select(&.tagger.==("flask_auth")).should be_empty
  end
end
