require "../../func_spec.cr"

# Plain `.nest("/p", X)` where the mounted sub-router's builder fn lives in
# another file. `webui::make_webui_router()` (direct call) and a `let`-bound
# `admin::admin_router()` are both resolved so the sub-router's own `.route()`
# calls compose the nest prefix (`/web`, `/admin`) instead of emitting at the
# root. `service::service_router().with_state(())` exercises the let-bound
# `nest_api_service` form used by aide/ApiRouter services. The same-file root
# route is unaffected.
expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/web/", "GET"),
  Endpoint.new("/web/assets/app.js", "GET"),
  Endpoint.new("/admin/users", "GET"),
  Endpoint.new("/service/status", "GET"),
]

tester = FunctionalTester.new("fixtures/rust/axum_crossfile_nest/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "only_techs" => YAML::Any.new("rust_axum"),
})
tester.perform_tests

it "names the fn a `get(handler)` route resolves to as its handler", tags: "functional" do
  src = "./spec/functional_test/fixtures/rust/axum_crossfile_nest/src"
  root = tester.app.endpoints.find! { |ep| ep.url == "/" }
  root.handler.should eq(Handler.new("root", "#{src}/main.rs", 12))
  users = tester.app.endpoints.find! { |ep| ep.url == "/admin/users" }
  users.handler.should eq(Handler.new("list_users", "#{src}/admin.rs", 8))
end
