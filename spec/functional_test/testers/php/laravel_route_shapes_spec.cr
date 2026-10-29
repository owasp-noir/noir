require "../../func_spec.cr"

# Laravel route shapes from #3302:
#   * `Route::resource('articles', 'ArticleController')` resolves its string
#     controller through the group namespace, like `'Controller@action'`;
#   * a FormRequest not named `*Request` (`LoginUser extends FormRequest`)
#     and `$request->only(...)` / `->except([...])` give params;
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

    params.call(find.call("POST", "/api/users/login")).should eq(["email", "password", "user.email", "user.password", "user.remember", "user.token"])

    find.call("POST", "/a/{config}")
    find.call("POST", "/b/x")
    find.call("POST", "/c/{prefix}")
    find.call("POST", "/d")

    ANY_ROUTE_HTTP_METHODS.each do |verb|
      find.call(verb, "/.well-known/carddav")
      find.call(verb, "/old")
    end
    endpoints.select { |ep| ep.url == "/welcome" }.map(&.method).should eq(["GET"])
  end
end
