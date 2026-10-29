require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

private def flask_detect(decorator : String) : Endpoint
  tmpdir = File.tempname("flask_auth_extra")
  Dir.mkdir_p(tmpdir)
  app = File.join(tmpdir, "app.py")
  File.write(app, [
    "@app.route('/secret')",
    decorator,
    "def secret():",
    "    return 'ok'",
  ].join("\n"))

  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(app, 1))
  details.technology = "python_flask"
  endpoint = Endpoint.new("/secret", "GET", [] of Param, details)

  FlaskAuthTagger.new(noir_options).perform([endpoint])
  FileUtils.rm_rf(tmpdir)
  endpoint
end

describe "FlaskAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/python/flask_auth", __DIR__)
  app_path = "#{fixture_base}/app.py"

  # app.py line reference — the route decorator, which is the line the
  # Flask analyzer reports:
  #  8: @app.route('/public')
  # 13: @app.route('/profile')       (@login_required below it)
  # 19: @app.route('/api/data', ...) (multi-line; @jwt_required() below it)
  # 34: @app.route('/misordered')    (@login_required *above* it)

  it "detects @login_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 13))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("flask_auth")
    endpoint.tags[0].description.should contain("login_required")
  end

  it "detects @jwt_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 19))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/api/data", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 8))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "does not tag a route whose auth decorator sits above the route decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 34))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/misordered", "GET", [] of Param, details)

    FlaskAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "still reads the decorators above a line that is the view itself" do
    tmpdir = File.tempname("flask_auth_def_line")
    Dir.mkdir_p(tmpdir)
    app = File.join(tmpdir, "app.py")
    File.write(app, "@app.route('/x')\n@login_required\ndef x():\n    return 'ok'\n")

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(app, 3))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)

    FlaskAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)

    endpoint.tags.map(&.name).should eq(["auth"])
  end

  it "detects bare @jwt_required (no parentheses)" do
    endpoint = flask_detect("@jwt_required")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "detects @jwt_required() call form" do
    endpoint = flask_detect("@jwt_required()")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("jwt_required")
  end

  it "detects flask-security @auth_required" do
    endpoint = flask_detect("@auth_required('token', 'session')")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("auth_required")
  end

  it "detects flask-security @permission_required" do
    endpoint = flask_detect("@permission_required('admin')")
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("permission_required")
  end

  # flask_setup_gated_guard/app.py: the view is reached when the app is
  # not set up (a setting) or when the caller is an admin, in the `and`
  # form and the nested form (#3292). `authed() and not is_admin()` lets
  # an anonymous caller through, so it is no guard.
  it "judges each path past a setup-gated refusal on its own" do
    base = File.expand_path("../../../functional_test/fixtures/python/flask_setup_gated_guard", __DIR__)
    app = "#{base}/app.py"
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    endpoints = {67 => "/setup/git", 73 => "/setup/nested", 79 => "/admin/thing", 85 => "/anyone", 113 => "/posts", 119 => "/scores"}.map do |line, url|
      details = Details.new(PathInfo.new(app, line))
      details.technology = "python_flask"
      Endpoint.new(url, "DELETE", [] of Param, details)
    end

    verdicts = FlaskAuthTagger.new(noir_options).perform(endpoints).map { |ep| {ep.url, ep.tags.select(&.name.== "auth").map(&.description)} }.to_h
    verdicts["/setup/git"].should eq(["Protected by managers_only (a setting can make it public)"])
    verdicts["/setup/nested"].should eq(["Protected by nested_managers_only (a setting can make it public)"])
    verdicts["/admin/thing"].should eq(["Protected by admins_only"])
    verdicts["/anyone"].should be_empty
    # A GET gets past `request.method == "POST" and ...`: the caller's choice.
    verdicts["/posts"].should be_empty
    # The `elif` refuses, but the public branch above it is a way in.
    verdicts["/scores"].should eq(["Protected by public_or_members (a setting can make it public)"])
  end
end
