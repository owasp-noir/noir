require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Each GET route `{line => url}` of one Micronaut controller as its tag
# names and its requirement.
private def micronaut_tags(name : String, source : Array(String), routes : Hash(Int32, String), extra : Hash(String, String) = {} of String => String) : Array({Array(String), Array(String)})
  tmpdir = File.tempname("micronaut_requires")
  Dir.mkdir_p(tmpdir)
  files = {File.join(tmpdir, name) => source.join("\n")}
  extra.each { |file, text| files[File.join(tmpdir, file)] = text }
  files.each do |file, text|
    File.write(file, text)
    CodeLocator.instance.register_path(file)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  endpoints = routes.map do |line, url|
    details = Details.new(PathInfo.new(File.join(tmpdir, name), line))
    details.technology = "java_micronaut"
    Endpoint.new(url, "GET", [] of Param, details)
  end
  MicronautAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.map { |endpoint| {endpoint.tags.map(&.name), Access.of(endpoint).map(&.to_s)} }
end

describe "MicronautAuthTagger" do
  before_each do
    CodeLocator.instance.clear_all
  end

  controller = [
    "@Secured(SecurityRule.IS_AUTHENTICATED)",               # 1
    "@Controller(\"/account\")",                             # 2
    "public class AccountController {",                      # 3
    "  @Get",                                                # 4
    "  public String me() { return \"me\"; }",               # 5
    "  @Get(\"/admin\")",                                    # 6
    "  @Secured({\"ROLE_ADMIN\", \"ROLE_ROOT\"})",           # 7
    "  public String admin() { return \"admin\"; }",         # 8
    "  @Get(\"/literal\")",                                  # 9
    "  @Secured(\"isAuthenticated()\")",                     # 10
    "  public String literal() { return \"literal\"; }",     # 11
    "  @Get(\"/off\")",                                      # 12
    "  @Secured(SecurityRule.DENY_ALL)",                     # 13
    "  public String off() { return \"off\"; }",             # 14
    "  @Get(\"/public\")",                                   # 15
    "  @Secured(SecurityRule.IS_ANONYMOUS)",                 # 16
    "  public String pub() { return \"pub\"; }",             # 17
    "  @Get(\"/expr\")",                                     # 18
    "  @Secured(\"\#{ user?.attributes?.get('a') == 1 }\")", # 19
    "  public String expr() { return \"expr\"; }",           # 20
    "}",                                                     # 21
  ]
  routes = {4 => "/account", 6 => "/account/admin", 9 => "/account/literal", 12 => "/account/off", 15 => "/account/public", 18 => "/account/expr"}

  it "reads @Secured, the method's in place of the class's" do
    micronaut_tags("AccountController.java", controller, routes).should eq([
      {["auth"], ["authenticated"]},
      {["auth"], ["(role:ROLE_ADMIN | role:ROLE_ROOT)"]},
      {["auth"], ["authenticated"]},
      {["auth"], ["deny"]},
      {["anonymous"], ["anonymous"]},
      {["auth"], ["authenticated", "unresolved"]},
    ])
  end

  it "keeps an app SecurityRule, which may decide first, unread" do
    rule = "public class TenantRule implements SecurityRule<HttpRequest<?>> {\n}"
    micronaut_tags("AccountController.java", controller, {4 => "/account", 15 => "/account/public"}, {"TenantRule.java" => rule}).should eq([
      {["auth"], ["authenticated", "unresolved"]},
      {["anonymous"], ["unresolved"]},
    ])
  end

  it "reads Kotlin varargs" do
    micronaut_tags("AccountController.kt", [
      "@Controller(\"/account\")",          # 1
      "class AccountController {",          # 2
      "  @Get",                             # 3
      "  @Secured(\"ROLE_A\", \"ROLE_B\")", # 4
      "  fun me(): String = \"me\"",        # 5
      "}",                                  # 6
    ], {3 => "/account"}).should eq([{["auth"], ["(role:ROLE_A | role:ROLE_B)"]}])
  end
end
