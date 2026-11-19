require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/php/symfony"

# Ratio, not wall clock: CI runners vary. 4x the routes must cost well under
# the 16x a per-route walk from the top of the controller would.
private def symfony_scan_time(count : Int32, yaml : Bool) : Time::Span
  temp_dir = File.tempname("symfony_scaling")
  controller = File.join(temp_dir, "src", "Controller", "BigController.php")
  routes = File.join(temp_dir, "config", "routes.yaml")
  Dir.mkdir_p(File.dirname(controller))
  Dir.mkdir_p(File.dirname(routes))
  File.write(controller, String.build do |io|
    io << "<?php\nnamespace App\\Controller;\nuse Symfony\\Component\\Routing\\Attribute\\Route;\nuse Symfony\\Component\\HttpFoundation\\Request;\nclass BigController\n{\n"
    count.times do |i|
      io << "    #[Route('/r#{i}/{id}', methods: ['GET'])]\n" unless yaml
      io << "    public function m#{i}(Request $request, int $id) { $x = $request->query->get('q#{i}'); return 1; }\n"
    end
    io << "}\n"
  end)
  File.write(routes, String.build do |io|
    count.times { |i| io << "r#{i}:\n    path: /r#{i}/{id}\n    controller: App\\Controller\\BigController::m#{i}\n" }
  end) if yaml

  CodeLocator.instance.clear_all
  CodeLocator.instance.register_file(controller, File.read(controller))
  CodeLocator.instance.register_file(routes, File.read(routes)) if yaml
  target = yaml ? routes : controller
  endpoints = [] of Endpoint
  elapsed = measure_without_gc { endpoints = Analyzer::Php::Symfony.new(create_test_options).analyze_file(target) }
  endpoints.size.should eq(count)
  last = endpoints.find!(&.url.==("/r#{count - 1}/{id}"))
  last.params.map(&.name).should eq(["id", "q#{count - 1}"])
  last.details.code_paths.first.line.should eq(yaml ? count * 3 - 2 : count * 2 + 5)
  last.handler.try(&.line).should eq(count + 6 + (yaml ? 0 : count))
  elapsed
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe Analyzer::Php::Symfony do
  it "analyzes many attribute routes in one controller in linear time" do
    small = symfony_scan_time(500, yaml: false)
    large = symfony_scan_time(2000, yaml: false)
    large.should be < (small * 8 + 500.milliseconds)
  end

  it "analyzes many YAML routes into one controller in linear time" do
    small = symfony_scan_time(500, yaml: true)
    large = symfony_scan_time(2000, yaml: true)
    large.should be < (small * 8 + 500.milliseconds)
  end
end
