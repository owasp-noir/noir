require "../../func_spec.cr"

# Armeria `Server.builder()` routes carry the line of their own registration
# and an `auth` tag when an `AuthService` decorator in the same chain covers
# them (#3268): a server-level `.decorator`/`.decoratorUnder` (prefix-scoped),
# or one passed to the route's own registration or `.route()...build()`.
# A neighbouring route's or annotated service's decorator, a commented-out
# one, another server's, or a class merely named `AuthServiceImpl` does not.
describe "Armeria builder routes and auth decorators", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "tags only the routes an AuthService decorator covers" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/java/armeria_auth/")])
    options["all_taggers"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    by_url = app.endpoints.to_h { |ep| {ep.url, ep} }
    {"/welcome" => 13, "/inline" => 14, "/other" => 15, "/admin/users" => 16}.each do |url, line|
      by_url[url].details.code_paths.first.line.should eq(line)
    end

    auth = ->(url : String) do
      endpoint = by_url[url]? || fail("missing #{url}; have #{by_url.keys}")
      endpoint.tags.select { |tag| tag.name == "auth" }.map(&.description)
    end
    guarded = ["Protected by Armeria AuthService decorator"]

    %w[/inline /admin/users /c3/admin /b/guarded /b/scoped/admin].each do |url|
      auth.call(url).should eq(guarded)
    end
    %w[/welcome /other /c1/public /c2/login /c3/open /c4/open /b/open /b/scoped/public /kt/docs /kt/public].each do |url|
      auth.call(url).should be_empty
    end

    # V.java: virtual-host blocks, path-pattern forms (a bare path is
    # exact; `prefix:`, `glob:` and `*` are not), a variable decorator, a
    # string that spells a decorator, and `.<T>service(` in the chain.
    %w[/v3/vh/admin /v3/vh/routeopen /v3/vh/inner /v3/admin /v3/p/x /v3/g/a/b /v3/x/y /v3/e /v3/gen/b].each do |url|
      auth.call(url).should eq(guarded)
    end
    %w[/v3/vh/pub /v3/vh/other /v3/vh/other2 /v3/vh/pub2 /v3/admin/open /v3/pp /v3/var/r /v3/str/r /v3/str/r2].each do |url|
      auth.call(url).should be_empty
    end
  end
end
