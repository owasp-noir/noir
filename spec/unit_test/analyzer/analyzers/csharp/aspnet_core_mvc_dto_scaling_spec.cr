require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/csharp/aspnet_core_mvc"

describe "ASP.NET Core MVC body DTO lookup scaling" do
  it "reads DTOs that share one file in linear time" do
    # Ratio, not wall clock: CI runners vary. 4x the actions must cost well
    # under the 16x a per-action re-read of the shared DTO file would.
    scan = ->(count : Int32) do
      temp_dir = File.tempname("noir_aspnet_dto_scaling")
      begin
        locator = CodeLocator.instance
        locator.clear_all
        models = File.join(temp_dir, "Models", "Models.cs")
        controllers = File.join(temp_dir, "Controllers", "ItemsController.cs")
        Dir.mkdir_p(File.dirname(models))
        Dir.mkdir_p(File.dirname(controllers))
        model_source = String.build do |io|
          io << "namespace App.Models;\n\n"
          count.times { |i| io << "public class Dto#{i}\n{\n    public string Name#{i} { get; set; }\n}\n\n" }
        end
        controller_source = String.build do |io|
          io << "using Microsoft.AspNetCore.Mvc;\nusing App.Models;\n\nnamespace App.Controllers;\n\n"
          io << "[Route(\"api/items\")]\npublic class ItemsController : ControllerBase\n{\n"
          count.times { |i| io << "    [HttpPost(\"a#{i}\")]\n    public IActionResult A#{i}([FromBody] Dto#{i} dto) => Ok();\n" }
          io << "}\n"
        end
        {models => model_source, controllers => controller_source}.each do |path, source|
          File.write(path, source)
          locator.register_file(path, source)
        end

        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
        endpoints = [] of Endpoint
        elapsed = measure_without_gc { endpoints = Analyzer::CSharp::AspNetCoreMvc.new(options).analyze }
        endpoints.size.should eq(count)
        last = endpoints.find! { |e| e.url == "/api/items/a#{count - 1}" }
        last.params.map(&.name).should eq(["name#{count - 1}"])
        elapsed
      ensure
        CodeLocator.instance.clear_all
        FileUtils.rm_rf(temp_dir)
      end
    end

    small = scan.call(250)
    large = scan.call(1000)
    large.should be < (small * 8 + 500.milliseconds)
  end
end
