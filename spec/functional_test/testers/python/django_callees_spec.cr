require "../../func_spec.cr"

# Regression test for --include-callee on Django. The fixture wires
# both view styles through the same urlpatterns table:
#
#   - `views.create_user`         → function-based view that calls
#                                    `request.POST.get`, `save_user`,
#                                    `audit_log`, `JsonResponse`. The
#                                    analyzer emits both GET and POST
#                                    for this view (GET is the default,
#                                    POST is inferred from
#                                    `request.POST.get`); both
#                                    endpoints must carry the same
#                                    callee list.
#   - `views.ProfileView.as_view` → class-based view with distinct
#                                    callees inside `def get` and
#                                    `def post`. This locks in
#                                    per-method callee scoping.
#
# Line assertions verify that body_start_line conversion (char-offset
# → 0-based line) lands correctly for both paths.
expected_endpoints = [
  # Django's `request.POST.get(...)` registers as a form param, and
  # `form` type accepts GET as well (existing REQUEST_PARAM_TYPE_MAP
  # behavior), so both GET and POST endpoints carry the same name.
  Endpoint.new("/users", "GET", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.POST.get", line: 8))
    ep.push_callee(Callee.new("save_user", line: 9))
    ep.push_callee(Callee.new("audit_log", line: 10))
    ep.push_callee(Callee.new("JsonResponse", line: 11))
  end,

  Endpoint.new("/users", "POST", [
    Param.new("name", "", "form"),
  ]).tap do |ep|
    ep.push_callee(Callee.new("request.POST.get", line: 8))
    ep.push_callee(Callee.new("save_user", line: 9))
    ep.push_callee(Callee.new("audit_log", line: 10))
    ep.push_callee(Callee.new("JsonResponse", line: 11))
  end,

  Endpoint.new("/profile", "GET").tap do |ep|
    ep.push_callee(Callee.new("build_profile", line: 16))
    ep.push_callee(Callee.new("audit_log", line: 17))
    ep.push_callee(Callee.new("JsonResponse", line: 18))
  end,

  Endpoint.new("/profile", "POST").tap do |ep|
    ep.push_callee(Callee.new("save_user", line: 21))
    ep.push_callee(Callee.new("audit_log", line: 22))
    ep.push_callee(Callee.new("JsonResponse", line: 23))
  end,
]

tester = FunctionalTester.new("fixtures/python/django_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "keeps Django class-based view callees scoped to each HTTP method" do
  get_endpoint = tester.app.endpoints.find { |endpoint| endpoint.url == "/profile" && endpoint.method == "GET" }
  post_endpoint = tester.app.endpoints.find { |endpoint| endpoint.url == "/profile" && endpoint.method == "POST" }

  get_endpoint.should_not be_nil
  post_endpoint.should_not be_nil

  get_endpoint.try do |endpoint|
    endpoint.callees.map(&.name).should eq(["build_profile", "audit_log", "JsonResponse"])
  end

  post_endpoint.try do |endpoint|
    endpoint.callees.map(&.name).should eq(["save_user", "audit_log", "JsonResponse"])
  end
end
