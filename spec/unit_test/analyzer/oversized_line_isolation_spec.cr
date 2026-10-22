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

# One unrelated source file with a multi-megabyte single line blows PCRE2's
# match limit in a whole-file regex. That used to raise out of the analyzer
# and the tech-level rescue dropped every endpoint the tech had found.
describe "oversized single-line source isolation" do
  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  {
    "python_flask" => {"app.py", %(from flask import Flask\napp = Flask(__name__)\n\n@app.route("/ok")\ndef ok():\n    return "ok"\n),
                       "data.py", "B = \"%s\"\n"},
    "lua_lor" => {"app.lua", %(local lor = require("lor.index")\nlocal app = lor()\napp:get("/ok", function(req, res, next) res:send("ok") end)\napp:run()\n),
                  "data.lua", "local B = \"use %s\"\n"},
  }.each do |tech, (app_name, app_source, data_name, data_template)|
    it "skips only the oversized file for #{tech}" do
      root = File.tempname("noir-#{tech}-big-line")
      begin
        Dir.mkdir_p(root)
        File.write(File.join(root, app_name), app_source)
        File.write(File.join(root, data_name), data_template % ("x" * 6_000_000))

        endpoints = scan_tree(root)

        endpoints.map(&.url).should contain("/ok")
        failure = Noir::SkippedFiles.failures.find! { |f| f.tech == tech }
        failure.message.should contain(data_name)
      ensure
        FileUtils.rm_rf(root)
      end
    end
  end
end
