require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/typescript/nestjs"
require "../../../../src/tagger/tagger"

# The tagger reads each route's decorators off the TypeScript AST: a
# `@UseGuards(` split over lines, a guard or `@Public()` in a comment, a
# guard named inside another decorator's string, and one-line handlers
# stacked in one class. `plain/` has no global guard; `global/` registers
# `JwtAuthGuard` as APP_GUARD.
private def nest_ast_tags : Hash(String, Array({String, String}))
  base = File.expand_path("../../../functional_test/fixtures/typescript/nestjs_auth_ast", __DIR__)
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob("#{base}/**/*").each { |path| locator.register_file(path, File.read(path)) if File.file?(path) }
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  endpoints = Analyzer::Typescript::Nestjs.new(options).analyze
  endpoints = NestjsAuthTagger.new(options).perform(endpoints)
  endpoints.to_h { |endpoint| {endpoint.url, endpoint.tags.map { |tag| {tag.name, tag.description} }} }
ensure
  CodeLocator.instance.clear_all
end

describe "NestjsAuthTagger on the decorator AST" do
  tags = nest_ast_tags

  it "reads a @UseGuards split over lines, and leaves a throttle-only one open" do
    tags["cases/multiline"].map(&.[0]).should eq(["auth"])
    tags["cases/throttle-only"].should be_empty
  end

  it "ignores a guard in a comment or inside another decorator's string" do
    tags["cases/commented-guard"].should be_empty
    tags["cases/guard-in-string"].should be_empty
  end

  it "reads RolesGuard after a called guard in the same list" do
    tags["cases/roles"].map(&.[0]).should eq(["auth", "authz"])
  end

  it "keeps a one-line handler's guard on it and off the next one" do
    tags["cases/one-line"].map(&.[0]).should eq(["auth"])
    tags["cases/after-one-line"].should be_empty
  end

  it "reads a multi-line applyDecorators bundle and class-level guards per class" do
    tags["cases/bundle"].first[1].should contain("@Auth()")
    tags["guarded"].first[1].should contain("(class-level)")
    tags["open"].should be_empty
  end

  it "does not let a commented-out @Public() open a route under a global guard" do
    tags["items/was-public"].map(&.[0]).should eq(["auth"])
    tags["items/public"].should be_empty
    tags["items/private"].map(&.[0]).should eq(["auth"])
  end
end
