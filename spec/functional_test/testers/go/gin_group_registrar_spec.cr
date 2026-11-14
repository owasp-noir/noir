require "../../func_spec.cr"

# apache/answer's layout: groups built in `server/http.go` with a prefix the
# scan cannot read (`r.Group(uiConf.APIBaseURL + "/answer/api/v1")`), given
# their `.Use` there, and handed to registrar methods in `router/`. The routes
# keep the prefix's literal tail, are marked `prefix: unresolved` (#3567), and
# carry a guard only when every call of their registrar hands it a guarded
# group.
expected_endpoints = [
  Endpoint.new("/answer/api/v1/siteinfo", "GET"),
  Endpoint.new("/answer/api/v1/user/login/email", "POST"),
  Endpoint.new("/answer/api/v1/personal/question/page", "GET"),
  Endpoint.new("/answer/api/v1/ai/conversation", "GET"),
  Endpoint.new("/answer/api/v1/ai/conversation", "DELETE"),
  Endpoint.new("/answer/api/v1/question/report", "POST"),
  Endpoint.new("/answer/admin/api/users/status", "PUT"),
  Endpoint.new("/answer/api/v1/connector/info", "GET"),
  # One registrar handed `authV1` and `adminV1`: once under each tail.
  Endpoint.new("/answer/api/v1/user-center/agent", "GET"),
  Endpoint.new("/answer/admin/api/user-center/agent", "GET"),
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/plain/ping", "GET"),
  Endpoint.new("/robots.txt", "GET"),
  Endpoint.new("/pages/about", "GET"),
]

tester = FunctionalTester.new("fixtures/go/gin_group_registrar/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "gin group prefix resolution", tags: "functional" do
  it "marks every route on a group whose prefix was not read in full, and no other" do
    tester.endpoints.reject(&.resolution).map { |ep| "#{ep.method} #{ep.url}" }.sort!.should eq(["GET /healthz", "GET /plain/ping"])
    tester.endpoints.compact_map(&.resolution).uniq!.should eq([{"prefix" => "unresolved"}])
  end
end

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
    guarded["GET /answer/api/v1/ai/conversation"].should be_true
    guarded["DELETE /answer/api/v1/ai/conversation"].should be_true
    guarded["POST /answer/api/v1/question/report"].should be_true
    guarded["PUT /answer/admin/api/users/status"].should be_true
    # Handed `authV1` and `adminV1`, both guarded.
    guarded["GET /answer/api/v1/user-center/agent"].should be_true
    guarded["GET /answer/admin/api/user-center/agent"].should be_true
    # `mustUnAuthV1` has no `.Use`.
    guarded["GET /answer/api/v1/siteinfo"].should be_false
    guarded["POST /answer/api/v1/user/login/email"].should be_false
    # `unAuthV1.Use(authMw.Auth(), authMw.EjectUserBySiteInfo())`: one lets
    # every caller through, the other is named for nothing that guards.
    guarded["GET /answer/api/v1/personal/question/page"].should be_false
    # Handed `mustUnAuthV1` and `authV1`.
    guarded["GET /answer/api/v1/connector/info"].should be_false
  end
end
