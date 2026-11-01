require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/nestjs"

describe "NestJS anonymous controller class" do
  it "names the handler by its method alone" do
    temp_dir = File.tempname("noir_nestjs_anonymous")
    begin
      Dir.mkdir_p(temp_dir)
      file = File.join(temp_dir, "a.controller.ts")
      content = "@Controller('x')\nexport default class {\n  @Get('a')\n  a() { return 1; }\n}\n"
      File.write(file, content)
      locator = CodeLocator.instance
      locator.clear_all
      locator.register_file(file, content)
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = Analyzer::Typescript::Nestjs.new(options).analyze
      endpoints.map { |e| e.handler.try(&.name) }.should eq(["a"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir) if temp_dir
    end
  end
end
