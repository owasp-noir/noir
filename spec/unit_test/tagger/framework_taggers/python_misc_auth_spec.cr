require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "PythonMiscAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/python/tornado_auth"
  app_path = "#{fixture_base}/app.py"

  # app.py line reference:
  #  4: class BaseHandler(tornado.web.RequestHandler):
  #  5:     def get_current_user(self):
  #  8: class MainHandler(BaseHandler):
  #  9:     @tornado.web.authenticated
  # 10:     def get(self):
  # 13: class ProfileHandler(BaseHandler):
  # 14:     @authenticated
  # 15:     def get(self):
  # 18: class PublicHandler(tornado.web.RequestHandler):
  # 19:     def get(self):

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects Tornado @tornado.web.authenticated decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/main", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("python_misc_auth")
    endpoint.tags[0].description.should contain("authenticated")
  end

  it "detects @authenticated shorthand decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 15))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("authenticated")
  end

  it "detects get_current_user override in class" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    # MainHandler has get_current_user inherited from BaseHandler
    # but here we test the class-level check by pointing to a line inside BaseHandler
    details = Details.new(PathInfo.new(app_path, 6))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/base", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    # get_current_user is defined on the class at line 5, check_class_auth walks backwards
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("get_current_user")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "python_tornado"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = PythonMiscAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "returns correct target_techs" do
    PythonMiscAuthTagger.target_techs.should contain("python_sanic")
    PythonMiscAuthTagger.target_techs.should contain("python_tornado")
  end
end
