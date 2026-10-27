require "../../func_spec.cr"

# In-handler caller checks judged by what the handler does: an `else` of
# `req.isAuthenticated()` that refuses, a refusal through a helper whose
# definition redirects to login, an earlier input-only refusal, and the
# shapes an anonymous caller gets past. Plus the params a handler reads
# through a helper and a formidable callback.
describe "Express in-handler auth checks and helper params", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "judges handler checks by their branches and reads helper params" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/express_handler_auth/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    find = ->(method : String, url : String) { endpoints.find! { |e| e.method == method && e.url == url } }
    guards_of = ->(method : String, url : String) do
      find.call(method, url).ai_context.try(&.guards.map(&.description)) || [] of String
    end
    params_of = ->(method : String, url : String) { find.call(method, url).params.map { |p| {p.name, p.param_type} } }

    guards_of.call("POST", "/history/:noteId").should eq(["Protected by Express handler check req.isAuthenticated() else returns errorForbidden"])
    guards_of.call("GET", "/me/delete/:token").should eq(["Protected by Express handler check !req.isAuthenticated() returns errorForbidden"])
    guards_of.call("GET", "/new").should eq(["Protected by Express handler check req.isAuthenticated() else returns errorForbidden — a setting can lift it"])
    {"/notes/:noteId" => "PUT", "/keyed" => "GET", "/either" => "GET", "/logout" => "GET"}.each do |url, method|
      guards_of.call(method, url).should be_empty
    end

    params_of.call("GET", "/new").should be_empty
    params_of.call("POST", "/login").should contain({"referer", "header"})
    params_of.call("POST", "/upload").sort.should eq([{"image", "file"}, {"title", "form"}])
  end
end
