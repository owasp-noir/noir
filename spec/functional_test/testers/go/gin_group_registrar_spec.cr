require "../../func_spec.cr"

# apache/answer's layout: groups built in `server/http.go` with a prefix the
# scan cannot read (`r.Group(uiConf.APIBaseURL + "/answer/api/v1")`), given
# their `.Use` there, and handed to registrar methods in `router/`. The routes
# keep the same-file convention for such a prefix (dropped), and carry a guard
# only when every call of their registrar hands it a guarded group.
expected_endpoints = [
  Endpoint.new("/siteinfo", "GET"),
  Endpoint.new("/user/login/email", "POST"),
  Endpoint.new("/personal/question/page", "GET"),
  Endpoint.new("/ai/conversation", "GET"),
  Endpoint.new("/ai/conversation", "DELETE"),
  Endpoint.new("/question/report", "POST"),
  Endpoint.new("/users/status", "PUT"),
  Endpoint.new("/connector/info", "GET"),
  Endpoint.new("/user-center/agent", "GET"),
]

FunctionalTester.new("fixtures/go/gin_group_registrar/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "go_auth on groups handed to registrars in another file", tags: "functional" do
  it "guards the routes of registrars handed only guarded groups" do
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/go/gin_group_registrar/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guarded = app.endpoints.to_h do |ep|
      {"#{ep.method} #{ep.url}", ep.tags.any? { |tag| tag.name == "auth" && tag.tagger == "go_auth" }}
    end
    # Handed only `authV1` / `adminV1`, each `.Use`d with a guard.
    guarded["GET /ai/conversation"].should be_true
    guarded["DELETE /ai/conversation"].should be_true
    guarded["POST /question/report"].should be_true
    guarded["PUT /users/status"].should be_true
    # Handed `authV1` and `adminV1`, both guarded.
    guarded["GET /user-center/agent"].should be_true
    # `mustUnAuthV1` has no `.Use`.
    guarded["GET /siteinfo"].should be_false
    guarded["POST /user/login/email"].should be_false
    # `unAuthV1.Use(authMw.Auth(), authMw.EjectUserBySiteInfo())`: one lets
    # every caller through, the other is named for nothing that guards.
    guarded["GET /personal/question/page"].should be_false
    # Handed `mustUnAuthV1` and `authV1`.
    guarded["GET /connector/info"].should be_false
  end
end
