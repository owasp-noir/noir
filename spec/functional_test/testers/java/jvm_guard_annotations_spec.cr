require "../../func_spec.cr"

module JvmGuardAnnotations
  def self.guards_of(fixture : String)
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(fixture)])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    ->(method : String, url : String) do
      endpoint = endpoints.find { |item| item.method == method && item.url == url }
      fail("missing #{method} #{url}; have #{endpoints.map { |item| "#{item.method} #{item.url}" }}") unless endpoint
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end
  end
end

# Quarkus login annotations and permission config, Micronaut's anonymous
# `@Secured`, and Spring's permitAll / anonymous `@Secured` (#3296).
describe "JVM auth annotations and permission config", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards Quarkus authenticated, deny, and permission paths, not permit" do
    guards = JvmGuardAnnotations.guards_of("./spec/functional_test/fixtures/java/quarkus_auth_guards/")

    guards.call("GET", "/admin").should eq(["Protected by Quarkus @Authenticated"])
    guards.call("GET", "/admin/off").should eq(["Protected by Quarkus @DenyAll"])
    guards.call("GET", "/admin/role").should contain("Protected by Quarkus @RolesAllowed")
    guards.call("GET", "/tokens/mine").should eq(["Protected by Quarkus permission policy authenticated (/tokens/*)"])
    guards.call("GET", "/admin/open").should be_empty
    guards.call("GET", "/public/page").should be_empty
    guards.call("GET", "/public/note").should be_empty
  end

  it "reads the Micronaut @Secured argument" do
    guards = JvmGuardAnnotations.guards_of("./spec/functional_test/fixtures/java/micronaut_auth_guards/")

    guards.call("GET", "/account").should contain("Protected by Micronaut @Secured")
    guards.call("GET", "/login/elsewhere").should contain("Protected by Micronaut @Secured")
    guards.call("GET", "/login/auth").should be_empty
    guards.call("GET", "/account/public").should be_empty
  end

  it "does not guard Spring permitAll or IS_AUTHENTICATED_ANONYMOUSLY" do
    guards = JvmGuardAnnotations.guards_of("./spec/functional_test/fixtures/java/spring_permitall_annotation/")

    guards.call("GET", "/public/a").should be_empty
    guards.call("GET", "/public/b").should be_empty
    guards.call("GET", "/public/e").should be_empty
    guards.call("GET", "/public/c").should eq(["Protected by Spring @PreAuthorize", "Protected by Spring @PreAuthorize"])
    guards.call("GET", "/public/d").should eq(["Protected by Spring @Secured", "Protected by Spring @Secured"])
  end
end
