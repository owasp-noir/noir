require "../../func_spec.cr"

# `r.Mount("/api/v1", apiv1.Routes())` where `Routes` is declared in
# another package: the mount prefix must reach every route the target
# registers (including a nested `Mount` inside it), and a root mount
# (`r.Mount("/", web.Routes())`) must not double the slash. Before this
# fixture every gitea API route was reported without its `/api/v1`.
expected_endpoints = [
  Endpoint.new("/healthz", "GET"),
  Endpoint.new("/metrics", "GET"),
  Endpoint.new("/api/v1/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}", "GET", [Param.new("owner", "", "path")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}/issues", "POST", [Param.new("title", "", "form")]),
  Endpoint.new("/api/v1/admin/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  # `{type:issues}` and `{type:pulls}` are two routes: the constraint stays.
  Endpoint.new("/api/v1/repos/{owner}/{repo}/{type:issues}/{index}", "GET", [Param.new("type", "", "path"), Param.new("index", "", "path")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}/{type:pulls}/{index}", "GET", [Param.new("type", "", "path")]),
  Endpoint.new("/api/v1/repos/{owner}/{repo}/contents/*", "GET"),
  # Route helpers declared in a sibling file and in an imported package,
  # called inside `r.Route("/{owner}/{repo}", ...)`: reported once, under
  # the caller's prefix, never again at the helper's own bare path.
  Endpoint.new("/{owner}/{repo}/info/refs", "GET"),
  Endpoint.new("/{owner}/{repo}/git-upload-pack", "POST"),
  Endpoint.new("/{owner}/{repo}/info/lfs/objects/batch", "POST"),
]

tester = FunctionalTester.new("fixtures/go/chi_crosspkg_mount/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names a mounted route's handler declared in an imported package", tags: "functional" do
  handlers = tester.app.endpoints.to_h { |ep| {ep.url, ep.handler} }
  issue_go = "./spec/functional_test/fixtures/go/chi_crosspkg_mount/routers/api/v1/repo/issue.go"
  handlers["/api/v1/repos/{owner}/{repo}/{type:issues}/{index}"].should eq(Handler.new("repo.GetIssue", issue_go, 6))
  handlers["/api/v1/repos/{owner}/{repo}/{type:pulls}/{index}"].should eq(Handler.new("repo.GetPull", issue_go, 9))
  handlers["/api/v1/repos/{owner}/{repo}/contents/*"].should eq(Handler.new("repo.GetContents", issue_go, 12))
  # An inline closure names no handler.
  handlers["/api/v1/users"].should be_nil
end

it "reads a route registered by a helper in another file from that file", tags: "functional" do
  root = "./spec/functional_test/fixtures/go/chi_crosspkg_mount/routers"
  refs = tester.app.endpoints.find! { |ep| ep.url == "/{owner}/{repo}/info/refs" }
  refs.details.code_paths.map { |cp| {cp.path, cp.line} }.should eq([{"#{root}/web/githttp.go", 10}])
  refs.handler.should eq(Handler.new("getInfoRefs", "#{root}/web/githttp.go", 14))
  lfs = tester.app.endpoints.find! { |ep| ep.url == "/{owner}/{repo}/info/lfs/objects/batch" }
  lfs.handler.should eq(Handler.new("BatchHandler", "#{root}/common/lfs.go", 14))
end
