require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "ExpressAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/javascript/express_auth"
  app_path = "#{fixture_base}/app.js"

  # app.js line reference:
  #  8: app.use('/admin', passport.authenticate('jwt', { session: false }));
  # 11: app.get('/public', (req, res) => {
  # 16: app.get('/profile', passport.authenticate('jwt', { session: false }), (req, res) => {
  # 21: app.post('/api/data', expressjwt({ secret: 'secret', algorithms: ['HS256'] }), (req, res) => {
  # 26: app.get('/dashboard', requireAuth, (req, res) => {
  # 31: app.get('/api/health', (req, res) => {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects passport.authenticate in route" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 16))
    details.technology = "js_express"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("express_auth")
    endpoint.tags[0].description.should contain("Passport")
  end

  it "detects expressjwt middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 21))
    details.technology = "js_express"
    endpoint = Endpoint.new("/api/data", "POST", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("JWT")
  end

  it "detects generic auth middleware (requireAuth)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 26))
    details.technology = "js_express"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("requireAuth")
  end

  it "detects ensureLoggedIn / ensureAuthenticated middleware (regression for 'enchure' typo)" do
    noir_options = create_test_options

    tmpdir = File.tempname("express_ensure")
    Dir.mkdir_p(tmpdir)
    js = File.join(tmpdir, "app.js")
    File.write(js, [
      "const express = require('express');",
      "const { ensureLoggedIn } = require('connect-ensure-login');",
      "const app = express();",
      "app.get('/secret', ensureLoggedIn(), (req, res) => {",
      "  res.json({ ok: true });",
      "});",
      "module.exports = app;",
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(js, 4))
    details.technology = "js_express"
    endpoint = Endpoint.new("/secret", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("ensureLoggedIn")

    FileUtils.rm_rf(tmpdir)
  end

  it "scans auth config under a SECOND base path (multi-root regression)" do
    base1 = File.tempname("express_base1")
    base2 = File.tempname("express_base2")
    Dir.mkdir_p(base1)
    Dir.mkdir_p(base2)
    # app.use auth config lives only under the second base path.
    File.write(File.join(base2, "auth.js"), "app.use('/admin', requireAuth);")
    routes = File.join(base2, "routes.js")
    File.write(routes, [
      "app.get('/admin/panel', (req, res) => {",
      "  res.json({});",
      "});",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new(base1), YAML::Any.new(base2)])

    locator = CodeLocator.instance
    [base1, base2].each do |b|
      Dir.glob("#{b}/**/*").each do |file|
        next if File.directory?(file)
        locator.push("file_map", file)
      end
    end

    details = Details.new(PathInfo.new(routes, 1))
    details.technology = "js_express"
    endpoint = Endpoint.new("/admin/panel", "GET", [] of Param, details)

    ExpressAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("app.use()")

    FileUtils.rm_rf(base1)
    FileUtils.rm_rf(base2)
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 31))
    details.technology = "js_express"
    endpoint = Endpoint.new("/api/health", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects app.use level auth for matching prefix" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # This endpoint has no auth on its own route definition,
    # but /admin prefix has app.use() level auth
    details = Details.new(PathInfo.new(app_path, 31))
    details.technology = "js_express"
    endpoint = Endpoint.new("/admin/settings", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("app.use()")
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "js_express"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = ExpressAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
