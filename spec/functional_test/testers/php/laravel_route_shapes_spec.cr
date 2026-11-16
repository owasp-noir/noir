require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# Laravel route shapes from #3302:
#   * `Route::resource('articles', 'ArticleController')` resolves its string
#     controller through the group namespace, like `'Controller@action'`;
#   * a FormRequest not named `*Request` (`LoginUser extends FormRequest`)
#     and `$request->only(...)` give params (`->except([...])` names
#     inputs the code drops, so it does not);
#   * a path built by `.` concatenation is kept, with literals folded and
#     other expressions as placeholders;
#   * `Route::redirect` / `permanentRedirect` answer every verb, `view` GET.
describe "Laravel route shapes", tags: "functional" do
  fixture = "./spec/functional_test/fixtures/php/laravel_route_shapes/"

  before_each do
    CodeLocator.instance.clear_all
  end

  it "resolves string resource controllers, FormRequests, concatenated paths and redirects" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
    find = ->(method : String, url : String) { endpoints.find! { |ep| ep.method == method && ep.url == url } }
    guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }
    params = ->(ep : Endpoint) { ep.params.map(&.name).sort! }

    articles = find.call("POST", "/api/articles")
    articles.handler.not_nil!.name.should eq("ArticleController@store")
    params.call(articles).should eq(["article.title"])
    guards.call(articles).should eq(guards.call(find.call("POST", "/api/drafts")))
    guards.call(articles).should_not be_empty

    params.call(find.call("POST", "/api/users/login")).should eq(["email", "password", "user.email", "user.password"])

    find.call("POST", "/a/{config}")
    find.call("POST", "/b/x")
    find.call("POST", "/c/{prefix}")
    find.call("POST", "/e/{trans}/f")
    find.call("POST", "/d")

    ANY_ROUTE_HTTP_METHODS.each do |verb|
      find.call(verb, "/.well-known/carddav")
      find.call(verb, "/old")
    end
    endpoints.select { |ep| ep.url == "/welcome" }.map(&.method).should eq(["GET"])
  end

  # `{post:slug}` names the column a model is bound by; the URL segment is
  # still one placeholder, which a `->where()` constraint may then narrow.
  it "keeps a scoped binding field out of the URL so the route traces" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints
    trace = ->(path : String) { Noir::CLI::Inspect.trace(endpoints, "GET", path).map(&.endpoint.url) }

    trace.call("/posts/hello-world").should eq(["/posts/{post}"])
    trace.call("/teams/acme/members/7").should eq(["/teams/{team}/members/{member?}"])
    trace.call("/teams/acme/members").should eq(["/teams/{team}/members/{member?}"])
    trace.call("/archive/2024").should eq(["/archive/{year:[0-9]+}"])
    endpoints.find! { |ep| ep.url == "/posts/{post}" }.params.map(&.name).should eq(["post"])
  end

  it "matches a long call argument in a concatenated path without exhausting the regex stack" do
    source = "Route::get('/a' . foo(#{" " * 200_000}), 'A@b');"
    source.match(Analyzer::Php::Laravel::VERB_REGEX).should_not be_nil
  end
end
