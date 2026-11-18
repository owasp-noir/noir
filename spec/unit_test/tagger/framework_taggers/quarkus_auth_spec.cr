require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

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
end
