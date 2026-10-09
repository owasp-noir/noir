require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/koa"
require "../../../../../src/analyzer/analyzers/javascript/oak"

# Cross-file mount prefixes resolve `./routes/v1` against an import
# boundary. That boundary used to be the *first* `-b`, so on a multi-base
# scan every file under a later base had its imports rejected and its
# routes lost their mount prefix — the URLs depended on `-b` order.
#
# `files` are relative to a temp root; each entry of `base_sets` is one scan
# whose `-b` list (relative to the same root) is given in order.
private def urls_per_scan(files : Hash(String, String), base_sets : Array(Array(String)), &analyze : Hash(String, YAML::Any) -> Array(Endpoint)) : Array(Array(String))
  temp_dir = File.tempname("noir_js_multibase")
  begin
    files.each do |rel, body|
      Dir.mkdir_p(File.dirname(File.join(temp_dir, rel)))
      File.write(File.join(temp_dir, rel), body)
    end

    base_sets.map do |bases|
      locator = CodeLocator.instance
      locator.clear_all
      Dir.glob(File.join(temp_dir, "**", "*")).each do |path|
        locator.register_file(path, File.read(path)) if File.file?(path)
      end
      options = create_test_options
      options["base"] = YAML::Any.new(bases.map { |b| YAML::Any.new(File.join(temp_dir, b)) })
      analyze.call(options).map(&.url).uniq!.sort!
    end
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(temp_dir) if temp_dir
  end
end

private def koa_router_js : String
  "const Router = require('koa-router');\nconst router = new Router();\nrouter.get('/status', ctx => { ctx.body = 'ok' });\nmodule.exports = router;\n"
end

private def sibling_bases : Array(Array(String))
  [["app", "other"], ["other", "app"]]
end

describe "JS cross-file import boundary on multi-base scans" do
  it "keeps the koa mount prefix whichever -b comes first" do
    files = {
      "app/routes/v1.js" => koa_router_js,
      "app/app.js"       => "const v1 = require('./routes/v1');\napp.use('/api/v1', v1.routes());\n",
      "other/index.js"   => "// unrelated\n",
    }
    urls_per_scan(files, sibling_bases) { |options| Analyzer::Javascript::Koa.new(options).analyze }.each do |urls|
      urls.should eq(["/api/v1/status"])
    end
  end

  it "keeps the oak mount prefix whichever -b comes first" do
    files = {
      "app/routes/v1.ts" => "import { Router } from 'https://deno.land/x/oak/mod.ts';\nconst router = new Router();\nrouter.get('/status', (ctx) => { ctx.response.body = 'ok' });\nexport default router;\n",
      "app/main.ts"      => "import v1 from './routes/v1.ts';\nconst router = new Router();\nrouter.use('/api/v1', v1.routes());\n",
      "other/index.js"   => "// unrelated\n",
    }
    urls_per_scan(files, sibling_bases) { |options| Analyzer::Javascript::Oak.new(options).analyze }.each do |urls|
      urls.should eq(["/api/v1/status"])
    end
  end

  # Nested bases: the longest-matching base of `svc/app.js` is `svc`, which
  # would reject `../shared/users` even though `.` is scanned too.
  it "lets a nested base import from its enclosing base in either order" do
    files = {
      "shared/users.js" => koa_router_js,
      "svc/app.js"      => "const users = require('../shared/users');\napp.use('/u', users.routes());\n",
    }
    urls_per_scan(files, [["."], [".", "svc"], ["svc", "."]]) { |options| Analyzer::Javascript::Koa.new(options).analyze }.each do |urls|
      urls.should eq(["/u/status"])
    end
  end
end
