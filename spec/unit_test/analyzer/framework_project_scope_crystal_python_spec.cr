require "../../spec_helper"
require "../../../src/models/noir"
require "../../../src/miniparsers/python_route_extractor_ts"
require "file_utils"

private def scan_tree(root : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

private def tech_sources(endpoints : Array(Endpoint), technology : String) : Array(String)
  endpoints.compact_map do |endpoint|
    next unless endpoint.details.technology == technology
    endpoint.details.code_paths.first?.try(&.path)
  end.uniq!
end

describe "analyzer project scoping (crystal, python)" do
  it "keeps Amber off Kemal's routes" do
    # `get "/path"` is the same line in Amber, Kemal and Grip, so a per-line
    # matcher cannot tell them apart — the file has to.
    root = File.tempname("noir-crystal-scope")

    begin
      FileUtils.mkdir_p(File.join(root, "shop", "src"))
      File.write(File.join(root, "shop", "shard.yml"), "name: shop\ndependencies:\n  amber:\n    github: amberframework/amber\n")
      File.write(File.join(root, "shop", "src", "shop.cr"), <<-CRYSTAL)
        require "amber"

        Amber::Server.configure do
          routes :web do
            get "/orders", OrdersController, :index
          end
        end
        CRYSTAL

      FileUtils.mkdir_p(File.join(root, "edge", "src"))
      File.write(File.join(root, "edge", "shard.yml"), "name: edge\ndependencies:\n  kemal:\n    github: kemalcr/kemal\n")
      File.write(File.join(root, "edge", "src", "edge.cr"), <<-CRYSTAL)
        require "kemal"

        get "/health" do
          "ok"
        end
        CRYSTAL

      endpoints = scan_tree(root)
      amber_sources = tech_sources(endpoints, "crystal_amber")
      amber_sources.any?(&.includes?("/shop/src/shop.cr")).should be_true
      amber_sources.any?(&.includes?("/edge/")).should be_false
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end

  describe Noir::TreeSitterPythonRouteExtractor do
    it "reads a leading bare verb as the method, not as the path" do
      # aiohttp's RouteTableDef spells its generic decorator
      # `@routes.route('PUT', '/profile')` — method first, path second. Taking
      # the first positional string blindly produced the route `/PUT`.
      source = <<-PYTHON
        @routes.route('PUT', '/profile')
        async def update_profile(request):
            return web.Response(text="ok")
        PYTHON

      decorations = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
      decorations.size.should eq(1)
      decorations[0].path.should eq("/profile")
      decorations[0].methods.should eq(["PUT"])
    end

    it "keeps a single positional string as the path even when it reads like a verb" do
      # `@app.route("/get")` is a path, not a method.
      source = <<-PYTHON
        @app.route("/get")
        def get_thing():
            return "x"
        PYTHON

      decorations = Noir::TreeSitterPythonRouteExtractor.extract_decorations(source)
      decorations.size.should eq(1)
      decorations[0].path.should eq("/get")
    end
  end
end
