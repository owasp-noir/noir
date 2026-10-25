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
      {"#{ep.method} #{ep.url}", ep.ai_context.try(&.guards.map { |g| "#{g.kind}:#{g.name}" }) || [] of String}
    end

    # login-manager answer, a 401 one call down through method_decorators
    # inherited from a base class, a composite returning another guard, and
    # a request key compared before a 404. A role used to look up the owner
    # in a query is not an authorization check.
    guards["GET /v1/profile"].should eq(["auth_guard:session_required"])
    guards["GET /v1/items/<int:item_id>"].should eq(["auth_guard:token_required"])
    guards["PUT /v1/settings"].should eq(["auth_guard:admission"])
    guards["POST /v1/inner/sync"].should eq(["auth_guard:inner_key_only"])
    # A role check is authorization: always for `admin_only`, and for
    # `admission` only where the call site passes `roles=`.
    guards["DELETE /v1/members/<int:member_id>"].should eq(["auth_guard:admission", "authz_guard:admission"])
    guards["GET /v1/audit/<int:entry_id>"].should eq(["auth_guard:session_required", "authz_guard:admin_only"])
    # A feature-flag 403 and a local no-op named `login_required` guard
    # nothing: the tagger reads both definitions. (The route-source scan
    # still name-matches `login_required` near the route, at low confidence.)
    # A wrapper is judged by the paths that reach the view: one that
    # needs a logged-in caller (read off `session` through a helper) is a
    # guard; one that lets the view run on a setting or a time window is
    # not, even when another branch refuses.
    guards["GET /v1/dashboard"].should eq(["auth_guard:members_only"])
    guards["GET /v1/stats"].should eq(["auth_guard:admins_only"])
    guards["GET /v1/scores"].should be_empty
    signup = app.endpoints.find! { |ep| ep.method == "POST" && ep.url == "/v1/signup" }
    signup.tags.select(&.tagger.==("flask_auth")).should be_empty
  end
end
