require "../../func_spec.cr"

# Echo routes whose path is `path.Join(const, "/seg")` and whose handler is
# a method value wrapped in middleware-style helpers (`a.page(hasID(
# a.ViewNote))`). The handler is the function value the wrappers hand in,
# and Echo's handler comes before trailing middleware (`POST(path, h, mw)`).
# `c.Bind(&v)` reads as the tagged fields of `v`'s struct (embedded structs
# included): `query` tags on GET, `json`/`form` tags on a body. `FormValue`
# reads the query string on GET, and a method the handler calls on its own
# receiver is one hop of the handler.
expected_endpoints = [
  Endpoint.new("/admin/notes/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/notes/:id", "PUT", [
    Param.new("id", "", "path"),
    Param.new("id", "", "json"),
    Param.new("title", "", "json"),
    Param.new("text", "", "json"),
  ]),
  Endpoint.new("/api/notes", "POST", [
    Param.new("id", "", "json"),
    Param.new("title", "", "form"),
    Param.new("tags", "", "json"),
  ]),
  Endpoint.new("/admin/forgot", "POST", [Param.new("email", "", "form")]),
  Endpoint.new("/subscribe", "GET", [
    Param.new("confirm", "", "query"),
    Param.new("l", "", "query"),
  ]),
  Endpoint.new("/subscribe", "POST", [
    Param.new("confirm", "", "form"),
    Param.new("l", "", "form"),
  ]),
  Endpoint.new("/stats", "GET", [
    Param.new("from", "", "query"),
    Param.new("to", "", "query"),
    Param.new("interval", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/go/echo_wrapped_handlers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "echo wrapped handlers", tags: "functional" do
  base = "./spec/functional_test/fixtures/go/echo_wrapped_handlers/main.go"

  it "names the function value a wrapped handler hands in" do
    note = tester.app.endpoints.find! { |ep| ep.url == "/admin/notes/:id" }
    note.handler.should eq(Handler.new("a.ViewNote", base, 67))
    forgot = tester.app.endpoints.find! { |ep| ep.url == "/admin/forgot" }
    forgot.handler.should eq(Handler.new("a.ForgotPage", base, 91))
  end

  it "takes Echo's first handler argument, not trailing middleware" do
    create = tester.app.endpoints.find! { |ep| ep.url == "/api/notes" }
    create.handler.should eq(Handler.new("a.CreateNote", base, 79))
  end

  it "drops the generic body marker when the bind target resolves" do
    update = tester.app.endpoints.find! { |ep| ep.url == "/api/notes/:id" }
    update.params.map(&.name).should_not contain("body")
    # `json:"-"` is never bound.
    update.params.map(&.name).should_not contain("Owner")
  end
end
