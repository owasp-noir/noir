require "../../spec_helper"
require "../../../src/models/noir"
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

# One source file holding thousands of routes used to be quadratic: every
# route re-split the whole file, re-joined the rest of it to cut out the
# handler body, and (for `add_url_rule(view_func=...)`) re-scanned it for
# the handler `def`.
describe "Python single-file route scaling" do
  {
    "flask" => {"from flask import Flask, request\napp = Flask(__name__)\n", "def"},
    "quart" => {"from quart import Quart, request\napp = Quart(__name__)\n", "async def"},
    "sanic" => {"from sanic import Sanic\napp = Sanic(\"a\")\n", "async def"},
  }.each do |framework, (header, def_kw)|
    it "scans a #{framework} file with thousands of routes in linear time" do
      routes = 3_000
      root = File.tempname("noir-#{framework}-scaling")
      begin
        Dir.mkdir_p(root)
        source = String.build do |io|
          io << header
          routes.times do |i|
            io << "\n@app.route(\"/r#{i}\")\n#{def_kw} r#{i}(request=None):\n    return request.args.get(\"q\")\n"
          end
          if framework == "flask"
            routes.times { |i| io << "\ndef v#{i}():\n    return request.args.get(\"q\")\n" }
            routes.times { |i| io << "app.add_url_rule(\"/v#{i}\", view_func=v#{i})\n" }
          end
        end
        File.write(File.join(root, "app.py"), source)

        endpoints = [] of Endpoint
        elapsed = Time.measure { endpoints = scan_tree(root) }

        endpoints.size.should eq(framework == "flask" ? routes * 2 : routes)
        # Generous wall-clock bound for slow CI runners: the quadratic version
        # took 12-110s at this size, the linear one about 1-2s.
        elapsed.should be < 20.seconds
      ensure
        FileUtils.rm_rf(root)
      end
    end
  end
end
