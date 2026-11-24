require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# The requirement of each GET route `{line => url}` of one Quarkus resource,
# with `properties` as its module's application.properties.
private def quarkus_requires(source : Array(String), properties : Array(String), routes : Hash(Int32, String), extra : Hash(String, String) = {} of String => String) : Array(Array(String))
  tmpdir = File.tempname("quarkus_requires")
  resources = File.join(tmpdir, "src/main/resources")
  sources = File.join(tmpdir, "src/main/java/com/example")
  Dir.mkdir_p(resources)
  Dir.mkdir_p(sources)
  files = {File.join(resources, "application.properties") => properties.join("\n"), File.join(sources, "ItemResource.java") => source.join("\n")}
  extra.each { |name, text| files[File.join(sources, name)] = text }
  files.each do |file, text|
    File.write(file, text)
    CodeLocator.instance.register_path(file)
  end
  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  endpoints = routes.map do |line, url|
    details = Details.new(PathInfo.new(File.join(sources, "ItemResource.java"), line))
    details.technology = "java_quarkus"
    Endpoint.new(url, "GET", [] of Param, details)
  end
  QuarkusAuthTagger.new(noir_options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  endpoints.map { |endpoint| Access.of(endpoint).map(&.to_s) }
end

describe "QuarkusAuthTagger" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards every path but the disabled ones under the Keycloak policy enforcer" do
    tmpdir = File.tempname("quarkus_policy_enforcer")
    resources = File.join(tmpdir, "src/main/resources")
    sources = File.join(tmpdir, "src/main/java/com/example")
    Dir.mkdir_p(resources)
    Dir.mkdir_p(sources)
    properties = File.join(resources, "application.properties")
    File.write(properties, [
      "quarkus.keycloak.policy-enforcer.enable=true",
      "quarkus.keycloak.policy-enforcer.paths.1.path=/api/public",
      "quarkus.keycloak.policy-enforcer.paths.1.enforcement-mode=DISABLED",
    ].join("\n"))
    resource = File.join(sources, "ItemResource.java")
    File.write(resource, [
      "@Path(\"/api\")",             # 1
      "public class ItemResource {", # 2
      "  @GET",                      # 3
      "  @Path(\"/items\")",         # 4
      "  public String items() {",   # 5
      "    return \"items\";",       # 6
      "  }",                         # 7
      "  @GET",                      # 8
      "  @Path(\"/public\")",        # 9
      "  public String open() {",    # 10
      "    return \"open\";",        # 11
      "  }",                         # 12
      "}",                           # 13
    ].join("\n"))
    CodeLocator.instance.register_path(properties)
    CodeLocator.instance.register_path(resource)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {5 => "/api/items", 10 => "/api/public"}.map do |line, url|
      details = Details.new(PathInfo.new(resource, line))
      details.technology = "java_quarkus"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    QuarkusAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)

    endpoints[0].tags.map(&.description).should eq(["Protected by Quarkus Keycloak policy enforcer"])
    endpoints[1].tags.should be_empty
  end

  it "leaves the paths alone while the Keycloak policy enforcer is off" do
    tmpdir = File.tempname("quarkus_policy_enforcer_off")
    Dir.mkdir_p(tmpdir)
    properties = File.join(tmpdir, "application.properties")
    File.write(properties, "quarkus.keycloak.policy-enforcer.enable=false\n")
    resource = File.join(tmpdir, "ItemResource.java")
    File.write(resource, "@Path(\"/api/items\")\npublic class ItemResource {\n  @GET\n  public String items() { return \"\"; }\n}\n")
    CodeLocator.instance.register_path(properties)
    CodeLocator.instance.register_path(resource)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(resource, 4))
    details.technology = "java_quarkus"
    endpoint = Endpoint.new("/api/items", "GET", [] of Param, details)
    QuarkusAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)

    endpoint.tags.should be_empty
  end

  # Tag descriptions per URL for a module whose properties files are given
  # by path relative to the module root.
  enforcer_tags = ->(properties : Hash(String, String), urls : Array(String)) do
    tmpdir = File.tempname("quarkus_enforcer")
    sources = File.join(tmpdir, "src/main/java/com/example")
    Dir.mkdir_p(sources)
    properties.each do |relative, content|
      file = File.join(tmpdir, relative)
      Dir.mkdir_p(File.dirname(file))
      File.write(file, content)
      CodeLocator.instance.register_path(file)
    end
    resource = File.join(sources, "ItemResource.java")
    File.write(resource, "@Path(\"/api\")\npublic class ItemResource {\n  @GET\n  public String items() { return \"\"; }\n}\n")
    CodeLocator.instance.register_path(resource)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    endpoints = urls.map do |url|
      details = Details.new(PathInfo.new(resource, 4))
      details.technology = "java_quarkus"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    QuarkusAuthTagger.new(noir_options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)
    endpoints.map(&.tags.map(&.description))
  end
  enforced = ["Protected by Quarkus Keycloak policy enforcer"]
  resources = "src/main/resources/application.properties"

  it "exempts a permit HTTP permission's paths from the Keycloak policy enforcer" do
    enforcer_tags.call({resources => "quarkus.keycloak.policy-enforcer.enable=true\n" \
                                     "quarkus.http.auth.permission.public.paths=/api/public\n" \
                                     "quarkus.http.auth.permission.public.policy=permit\n"},
      ["/api/public", "/api/items"]).should eq([[] of String, enforced])
  end

  it "reads a DISABLED enforcer path under a quoted name with a dot" do
    enforcer_tags.call({resources => "quarkus.keycloak.policy-enforcer.enable=true\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.\"public.docs\".paths=/api/public/docs\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.\"public.docs\".enforcement-mode=DISABLED\n"},
      ["/api/public/docs", "/api/items"]).should eq([[] of String, enforced])
  end

  it "reads a DISABLED enforcer path ending in /* as covering its parent path" do
    enforcer_tags.call({resources => "quarkus.keycloak.policy-enforcer.enable=true\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.1.path=/api/public/*\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.1.enforcement-mode=DISABLED\n"},
      ["/api/public", "/api/public/docs", "/api/items"]).should eq([[] of String, [] of String, enforced])
  end

  it "leaves a path alone when one of its enforcer methods is DISABLED" do
    enforcer_tags.call({resources => "quarkus.keycloak.policy-enforcer.enable=true\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.1.paths=/api/items\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.1.methods.get.method=GET\n" \
                                     "quarkus.keycloak.policy-enforcer.paths.1.methods.get.scopes-enforcement-mode=DISABLED\n"},
      ["/api/items", "/api/orders"]).should eq([[] of String, enforced])
  end

  it "lets the module's own properties file decide over a stray one at its root" do
    enforcer_tags.call({"application.properties" => "quarkus.keycloak.policy-enforcer.enable=true\n",
                        resources                => "quarkus.keycloak.policy-enforcer.enable=false\n"},
      ["/api/items"]).should eq([[] of String])
  end

  it "reads the annotation on the method in place of the class's, with every repeated @PermissionsAllowed" do
    quarkus_requires([
      "@Path(\"/items\")",                                                     # 1
      "@RolesAllowed(\"staff\")",                                              # 2
      "public class ItemResource {",                                           # 3
      "  @GET",                                                                # 4
      "  @PermissionsAllowed(value = {\"read\", \"list\"}, inclusive = true)", # 5
      "  @PermissionsAllowed(\"audit\")",                                      # 6
      "  public String all() { return \"all\"; }",                             # 7
      "  @GET",                                                                # 8
      "  @Path(\"/mine\")",                                                    # 9
      "  public String mine() { return \"mine\"; }",                           # 10
      "  @GET",                                                                # 11
      "  @RolesAllowed({",                                                     # 12
      "    \"admin\",",                                                        # 13
      "    \"root\"})",                                                        # 14
      "  public String admin() { return \"admin\"; }",                         # 15
      "  @GET",                                                                # 16
      "  @RolesAllowed(\"${admin.role}\")",                                    # 17
      "  public String configured() { return \"c\"; }",                        # 18
      "}",                                                                     # 19
    ], [] of String, {4 => "/items", 8 => "/items/mine", 11 => "/items/admin", 16 => "/items/configured"}).should eq([
      ["permission:read", "permission:list", "permission:audit"],
      ["role:staff"],
      ["(role:admin | role:root)"],
      ["authenticated", "unresolved"],
    ])
  end

  it "adds the HTTP permission that applies to the annotation's requirement" do
    quarkus_requires([
      "@Path(\"/api\")",                               # 1
      "public class ItemResource {",                   # 2
      "  @GET",                                        # 3
      "  @RolesAllowed(\"user\")",                     # 4
      "  public String items() { return \"items\"; }", # 5
      "  @GET",                                        # 6
      "  @Path(\"/admin/x\")",                         # 7
      "  public String admin() { return \"admin\"; }", # 8
      "  @GET",                                        # 9
      "  @Path(\"/custom\")",                          # 10
      "  public String custom() { return \"c\"; }",    # 11
      "  @GET",                                        # 12
      "  @Path(\"/off\")",                             # 13
      "  @PermitAll",                                  # 14
      "  public String off() { return \"off\"; }",     # 15
      "  @GET",                                        # 16
      "  @Path(\"/posts\")",                           # 17
      "  public String posts() { return \"posts\"; }", # 18
    ].push("}"), [
      "quarkus.http.auth.permission.api.paths=/api/*",
      "quarkus.http.auth.permission.api.policy=admins",
      "quarkus.http.auth.policy.admins.roles-allowed=admin,root",
      "quarkus.http.auth.permission.admin.paths=/api/admin/*",
      "quarkus.http.auth.permission.admin.policy=authenticated",
      "quarkus.http.auth.permission.audit.paths=/api/*",
      "quarkus.http.auth.permission.audit.policy=auditors",
      "quarkus.http.auth.permission.audit.shared=true",
      "quarkus.http.auth.policy.auditors.roles.root=admin",
      "quarkus.http.auth.permission.custom.paths=/api/custom",
      "quarkus.http.auth.permission.custom.policy=my-bean-policy",
      "quarkus.http.auth.permission.off.paths=/api/off",
      "quarkus.http.auth.permission.off.policy=deny",
      "quarkus.http.auth.permission.posts.paths=/api/posts",
      "quarkus.http.auth.permission.posts.policy=permit",
      "quarkus.http.auth.permission.posts.methods=POST",
    ], {3 => "/api/items", 6 => "/api/admin/x", 9 => "/api/custom", 12 => "/api/off", 16 => "/api/posts"}).should eq([
      # `/api/*` wins `api`, and the shared `audit` (a role policy without
      # `roles-allowed`: any signed-in caller) applies too.
      ["role:user", "(role:admin | role:root)", "authenticated"],
      ["authenticated"],
      # An app `HttpSecurityPolicy` bean.
      ["authenticated", "unresolved"],
      ["authenticated", "deny", "anonymous"],
      # `/api/posts` lists POST only: Quarkus refuses this GET unless
      # another permission admits it, which noir does not read.
      ["unresolved", "(role:admin | role:root)", "authenticated"],
    ])
  end

  it "leaves a permission an app @PermissionChecker decides unread" do
    quarkus_requires([
      "@Path(\"/items\")",                             # 1
      "public class ItemResource {",                   # 2
      "  @GET",                                        # 3
      "  @PermissionsAllowed({\"rename\", \"read\"})", # 4
      "  public String items() { return \"items\"; }", # 5
      "}",                                             # 6
    ], [] of String, {3 => "/items"}, {"Checks.java" => "class Checks {\n  @PermissionChecker(\"rename\")\n  boolean canRename(SecurityIdentity id) { return true; }\n}"}).should eq([
      ["authenticated", "(permission:read | unresolved)"],
    ])
  end

  it "keeps the settings it does not read unread: profile overrides, disabled permissions, Jakarta REST defaults and code-defined policies" do
    quarkus_requires([
      "@Path(\"/api\")",                               # 1
      "public class ItemResource {",                   # 2
      "  @GET",                                        # 3
      "  @Path(\"/items\")",                           # 4
      "  public String items() { return \"items\"; }", # 5
      "  @GET",                                        # 6
      "  @Path(\"/roles\")",                           # 7
      "  @RolesAllowed(\"user\")",                     # 8
      "  public String roles() { return \"roles\"; }", # 9
      "}",                                             # 10
    ], [
      "quarkus.http.auth.permission.api.paths=/api/*",
      "quarkus.http.auth.permission.api.policy=authenticated",
      "%prod.quarkus.http.auth.permission.api.policy=deny",
      "quarkus.http.auth.permission.old.paths=/api/roles",
      "quarkus.http.auth.permission.old.policy=deny",
      "quarkus.http.auth.permission.old.enabled=false",
      "quarkus.security.jaxrs.deny-unannotated-endpoints=true",
    ], {3 => "/api/items", 6 => "/api/roles"}, {"Security.java" => "class Security {\n  void configure(@Observes HttpSecurity httpSecurity) {}\n}"}).should eq([
      # The profile override, the Jakarta REST default, the observer, then `api`.
      ["unresolved", "unresolved", "unresolved", "authenticated"],
      # The Jakarta REST default needs an endpoint without annotations; the
      # disabled `old` hides which permission applies.
      ["role:user", "unresolved", "unresolved", "unresolved"],
    ])
  end
end
