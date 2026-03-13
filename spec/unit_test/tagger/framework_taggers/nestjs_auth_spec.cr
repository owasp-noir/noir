require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "NestjsAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/javascript/nestjs_auth"
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

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
  end
end
