require "../../func_spec.cr"

# #3316: a Nextcloud action inherited from a parent controller keeps its
# handler, params and guard (and an unresolvable one keeps the default
# login + admin guard); a Symfony docblock `@Route` over a commented-out
# method registers nothing; API Platform `security:` is a guard and
# property `#[QueryParameter]` / write-group fields are params.
describe "Nextcloud / Symfony / API Platform shapes", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/#{fixture}/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end
  find = ->(endpoints : Array(Endpoint), method : String, url : String) { endpoints.find! { |e| e.method == method && e.url == url } }
  guards = ->(ep : Endpoint) { ep.ai_context.try(&.guards.map(&.name)) || [] of String }

  it "resolves inherited Nextcloud actions" do
    endpoints = scan.call("nextcloud_inherit")
    v11 = find.call(endpoints, "GET", "/apps/deck/api/v1.1/attachments/{type}/{attachmentId}")
    guards.call(v11).should eq(["Nextcloud login (NoAdminRequired)"])
    v11.params.map(&.name).sort!.should eq(["attachmentId", "type"])
    v11.details.code_paths.map(&.path).any?(&.ends_with?("AttachmentApiController.php")).should be_true
    guards.call(find.call(endpoints, "GET", "/apps/deck/api/missing")).should eq(["Nextcloud login + admin (default)"])
  end

  it "skips a docblock route whose method is commented out" do
    endpoints = scan.call("symfony_commented_route")
    endpoints.map(&.url).sort!.should eq(["/config/attributed", "/config/otp/app"])
  end

  it "reads API Platform security and property params" do
    endpoints = scan.call("api_platform_security")
    guards.call(find.call(endpoints, "GET", "/admin/books")).should_not be_empty
    admin_post = find.call(endpoints, "POST", "/admin/books")
    guards.call(admin_post).should_not be_empty
    admin_post.params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(["title:json"])
    guards.call(find.call(endpoints, "DELETE", "/books/{id}")).should_not be_empty
    open = find.call(endpoints, "GET", "/books")
    guards.call(open).should be_empty
    open.params.map { |p| "#{p.name}:#{p.param_type}" }.should eq(["title:query"])
  end
end
