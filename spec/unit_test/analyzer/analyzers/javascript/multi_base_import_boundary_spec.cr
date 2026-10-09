require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/koa"
require "../../../../../src/analyzer/analyzers/javascript/oak"

# Cross-file mount prefixes resolve `./routes/v1` against an import
# boundary. That boundary used to be the *first* `-b`, so on a multi-base
# scan every file under a later base had its imports rejected and its
# routes lost their mount prefix — the URLs depended on `-b` order.
private def urls_in_both_orders(files : Hash(String, String), &analyze : Hash(String, YAML::Any) -> Array(Endpoint)) : Array(Array(String))
  temp_dir = File.tempname("noir_js_multibase")
  app = File.join(temp_dir, "app")
  other = File.join(temp_dir, "other")
  begin
    files.each do |rel, body|
      Dir.mkdir_p(File.dirname(File.join(app, rel)))
      File.write(File.join(app, rel), body)
    end
    Dir.mkdir_p(other)
    File.write(File.join(other, "index.js"), "// unrelated\n")

    [[app, other], [other, app]].map do |bases|
      locator = CodeLocator.instance
      locator.clear_all
      Dir.glob(File.join(temp_dir, "**", "*")).each do |path|
        locator.register_file(path, File.read(path)) if File.file?(path)
      end
      options = create_test_options
      options["base"] = YAML::Any.new(bases.map { |b| YAML::Any.new(b) })
      analyze.call(options).map(&.url).uniq!.sort!
    end
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end

describe "JS cross-file import boundary on multi-base scans" do
  it "keeps the koa mount prefix whichever -b comes first" do
    files = {
      "routes/v1.js" => "const Router = require('koa-router');\nconst router = new Router();\nrouter.get('/status', ctx => { ctx.body = 'ok' });\nmodule.exports = router;\n",
      "app.js"       => "const v1 = require('./routes/v1');\napp.use('/api/v1', v1.routes());\n",
    }
    urls_in_both_orders(files) { |options| Analyzer::Javascript::Koa.new(options).analyze }.each do |urls|
      urls.should eq(["/api/v1/status"])
    end
  end

  it "keeps the oak mount prefix whichever -b comes first" do
    files = {
      "routes/v1.ts" => "import { Router } from 'https://deno.land/x/oak/mod.ts';\nconst router = new Router();\nrouter.get('/status', (ctx) => { ctx.response.body = 'ok' });\nexport default router;\n",
      "main.ts"      => "import v1 from './routes/v1.ts';\nconst router = new Router();\nrouter.use('/api/v1', v1.routes());\n",
    }
    urls_in_both_orders(files) { |options| Analyzer::Javascript::Oak.new(options).analyze }.each do |urls|
      urls.should eq(["/api/v1/status"])
    end
  end
end
