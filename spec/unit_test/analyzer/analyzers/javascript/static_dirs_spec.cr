require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/express"

# `process_js_static_dirs` de-duplicated each static file against the whole
# result with `result.any?`, so a large asset tree cost O(files * result):
# 20k files took ~9s.
describe "JavascriptEngine static dirs" do
  it "emits one GET per static file in linear time and keeps declared routes" do
    temp_dir = File.tempname("noir_js_static_dirs")
    begin
      Dir.mkdir_p(temp_dir)
      app = File.join(temp_dir, "app.js")
      File.write(app, <<-JS)
        const express = require('express');
        const app = express();
        app.use(express.static('public'));
        app.get('/f0.txt', (req, res) => res.send('dynamic'));
        JS

      locator = CodeLocator.instance
      locator.clear_all
      locator.register_file(app, File.read(app))
      n = 20_000
      n.times { |i| locator.register_file(File.join(temp_dir, "public", "f#{i}.txt"), "") }

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Javascript::Express.new(options).analyze }

      elapsed.should be < 2.seconds
      endpoints.count { |e| e.method == "GET" }.should eq(n)
      endpoints.select { |e| e.url == "/f0.txt" }.map(&.details.code_paths.first.path).should eq([app])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
