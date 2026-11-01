require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/n8n"

# n8n's registries decide auth, not a middleware argument: a REST/root route
# is behind the auth cookie unless its options say `skipAuth: true` or
# `allowUnauthenticated: true`; a public API route always authenticates; a
# scope decorator refuses an anonymous caller by itself.
private def n8n_endpoints(fixture = "n8n") : Array(Endpoint)
  base = File.expand_path("../../../../functional_test/fixtures/typescript/#{fixture}", __DIR__)
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob(File.join(base, "**", "*.ts")).each { |path| locator.register_file(path, File.read(path)) }
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  Analyzer::Typescript::N8n.new(options).analyze
ensure
  CodeLocator.instance.clear_all
end

private def auth_of(endpoints : Array(Endpoint), method : String, url : String) : String?
  endpoint = endpoints.find! { |e| e.method == method && e.url == url }
  endpoint.tags.find { |tag| tag.name == "auth" }.try(&.description)
end

describe "n8n decorator controller auth" do
  endpoints = n8n_endpoints

  it "opens a route only on a literal skipAuth/allowUnauthenticated true" do
    auth_of(endpoints, "POST", "/rest/login").should be_nil
    auth_of(endpoints, "GET", "/rest/préférences").should be_nil
    auth_of(endpoints, "GET", "/rest/me").not_nil!.should contain("auth cookie")
  end

  it "does not read skipAuth out of a string or a comment" do
    auth_of(endpoints, "GET", "/rest/describe").not_nil!.should contain("auth cookie")
    endpoints.any?(&.url.includes?("commented")).should be_false
  end

  it "keeps a setting-dependent route guarded and names the setting" do
    auth_of(endpoints, "GET", "/rest/resolve-signup-token").not_nil!.should contain("a setting can open it")
  end

  it "does not hand one member's options to the next" do
    auth_of(endpoints, "GET", "/rest/workflows/public-ping").should be_nil
    auth_of(endpoints, "PATCH", "/rest/workflows/:workflowId").not_nil!.should contain("auth cookie")
  end

  it "counts a scope decorator as a guard even with skipAuth" do
    auth_of(endpoints, "GET", "/rest/workflows/:workflowId").not_nil!.should contain("ProjectScope workflow:read")
    auth_of(endpoints, "DELETE", "/rest/workflows/:workflowId").not_nil!.should contain("GlobalScope workflow:delete")
  end

  it "guards every public API route, whatever its options" do
    auth_of(endpoints, "GET", "/api/v1/tags/:tagId").not_nil!.should contain("public API")
    auth_of(endpoints, "GET", "/api/v1/tags").not_nil!.should contain("ApiKeyScope tag:list")
  end

  it "reads imported route options and their auth middleware" do
    auth_of(endpoints, "PUT", "/scim/v2/Users/:id").not_nil!.should contain("scimAuth")
    # A feature gate or a logger in the list is not a caller check.
    auth_of(endpoints, "GET", "/scim/v2/ServiceProviderConfig").should be_nil
  end
end

# Review cases: options read as code (comments stripped, top-level keys
# only, per decorator), consts through a barrel and a spread, non-literal
# scopes and middleware lists.
describe "n8n decorator controller auth, options read as code" do
  endpoints = n8n_endpoints("n8n_auth")
  cookie = "Protected by n8n auth cookie (ControllerRegistry auth middleware)"

  it "ignores a commented skipAuth in an options const or its declaration" do
    {"/rest/a/imported-commented", "/rest/a/local-commented", "/rest/c/legacy", "/rest/c/line-commented"}.each do |url|
      auth_of(endpoints, "GET", url).should eq(cookie)
    end
  end

  it "reads only the options' own top-level keys, of the decorator that declared the route" do
    auth_of(endpoints, "GET", "/rest/a/nested").should eq(cookie)
    auth_of(endpoints, "GET", "/rest/a/imported-str").should eq(cookie)
    auth_of(endpoints, "GET", "/rest/d/public").should be_nil
    auth_of(endpoints, "GET", "/rest/d/private").should eq(cookie)
  end

  it "opens on a literal true through a spread, a barrel, an import or across lines" do
    {"/rest/a/spread", "/rest/a/barrel-open", "/rest/a/direct-open", "/rest/a/multiline"}.each do |url|
      auth_of(endpoints, "GET", url).should be_nil
    end
  end

  it "counts a scope decorator with a const argument as a guard" do
    auth_of(endpoints, "GET", "/rest/a/scope-const").not_nil!.should contain("GlobalScope SCOPE")
  end

  it "notes a preview-mode skip and a middleware list built elsewhere" do
    auth_of(endpoints, "GET", "/rest/a/preview").not_nil!.should contain("N8N_PREVIEW_MODE")
    auth_of(endpoints, "POST", "/rest/a/dynamic").not_nil!.should contain("getDynamicCredentialMiddlewares()")
  end

  it "takes only an auth-shaped middleware name as the route's guard" do
    auth_of(endpoints, "GET", "/rest/a/oauth-cb").should be_nil
    auth_of(endpoints, "POST", "/rest/a/own-auth").not_nil!.should contain("getAuthMiddleware")
    # n8n's app sign-in: a const list holding only a cookie parser.
    auth_of(endpoints, "GET", "/rest/a/sign-in").should be_nil
  end

  it "keeps a literal false and a non-literal value guarded" do
    auth_of(endpoints, "GET", "/rest/a/false").should eq(cookie)
    auth_of(endpoints, "POST", "/rest/a/allow-false").should eq(cookie)
    auth_of(endpoints, "GET", "/rest/a/isdev").not_nil!.should contain("a setting can open it")
    auth_of(endpoints, "GET", "/rest/a/neg").not_nil!.should contain("a setting can open it")
  end
end
