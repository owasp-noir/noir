require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "NestjsAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/nestjs_auth", __DIR__)
  controller_path = "#{fixture_base}/src/posts.controller.ts"

  # posts.controller.ts line reference:
  #  8: @Controller('posts')
  #  9: @UseGuards(JwtAuthGuard)
  # 10: export class PostsController {
  # 12:   @Public()
  # 13:   @Get()
  # 14:   findAll() {
  # 18:   @Get(':id')
  # 19:   findOne() {
  # 23:   @Roles('admin')
  # 24:   @Post()
  # 25:   create() {
  # 29:   @Roles('admin')
  # 30:   @Delete(':id')
  # 31:   remove() {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects class-level @UseGuards(JwtAuthGuard) on non-public action" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 19))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/1", "GET", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("nestjs_auth")
    endpoint.tags[0].description.should contain("JwtAuthGuard")
  end

  it "respects @Public() decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects @Roles decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 25))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.any? { |t| t.name == "authz" && t.description.includes?("@Roles") }.should be_true
  end

  it "stacks class JwtAuthGuard authn with method @Roles authz" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 31))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/:id", "DELETE", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.map(&.name).sort!.should eq(["auth", "authz"])
    endpoint.tags.find! { |t| t.name == "auth" }.description.should contain("JwtAuthGuard")
    endpoint.tags.find! { |t| t.name == "authz" }.description.should contain("@Roles")
  end

  it "detects RolesGuard anywhere in combined @UseGuards(JwtAuthGuard, RolesGuard)" do
    tmpdir = File.tempname("nestjs_combined_guards")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "posts.controller.ts")
    File.write(path, [
      "@Controller('posts')",
      "export class PostsController {",
      "  @UseGuards(JwtAuthGuard, RolesGuard)",
      "  @Delete(':id')",
      "  remove() {",
      "    return {};",
      "  }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(path, 5))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/:id", "DELETE", [] of Param, details)

    NestjsAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.map(&.name).sort!.should eq(["auth", "authz"])
    endpoint.tags.find! { |t| t.name == "auth" }.description.should contain("JwtAuthGuard")
    endpoint.tags.find! { |t| t.name == "authz" }.description.should contain("RolesGuard")

    FileUtils.rm_rf(tmpdir)
  end
end
