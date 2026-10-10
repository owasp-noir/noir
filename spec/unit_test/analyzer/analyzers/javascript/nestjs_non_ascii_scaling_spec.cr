require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/typescript/nestjs"

# Every route decorator matched its parens, sliced its arguments and looked
# up its method by char index, and each of those re-decodes (or
# re-materializes) the class from the start once it holds a single
# non-ASCII char: 1000 routes with a Korean Swagger summary took ~19s.
describe "NestJS non-ASCII controller scaling" do
  it "scans a large non-ASCII controller in linear time, on the right lines" do
    temp_dir = File.tempname("noir_nestjs_non_ascii")
    begin
      Dir.mkdir_p(File.join(temp_dir, "src"))
      file = File.join(temp_dir, "src", "users.controller.ts")
      content = String.build do |io|
        io << "import { Controller, Get, Param } from '@nestjs/common';\n\n@Controller('users')\nexport class UsersController {\n"
        1000.times do |i|
          io << "  @Get('u#{i}/:id')\n  @ApiOperation({ summary: '사용자 조회 #{i}' })\n  @UseGuards(AuthGuard)\n"
          io << "  async m#{i}(@Param('id') id: string, @Query('q#{i}') q: string) {\n    return id;\n  }\n"
        end
        io << "}\n"
      end
      File.write(file, content)

      locator = CodeLocator.instance
      locator.clear_all
      locator.register_file(file, content)

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Typescript::Nestjs.new(options).analyze }

      endpoints.size.should eq(1000)
      last = endpoints.find! { |e| e.url == "users/u999/:id" }
      last.params.map(&.name).sort!.should eq(["id", "q999"])
      last.details.code_paths.first.line.should eq(5 + 999 * 6)
      elapsed.should be < 3.seconds
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
