require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "FlaskAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/python/flask_auth"
  app_path = "#{fixture_base}/app.py"

  # app.py line reference:
  #  9: @app.route('/public')
  # 10: def public_page():
  # 14: @login_required
  # 15: @app.route('/profile')
  # 16: def profile():
  # 20: @jwt_required()
  # 21: @app.route('/api/data')
  # 22: def api_data():

  it "detects @login_required decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(app_path, 16))
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

    details = Details.new(PathInfo.new(app_path, 22))
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

    details = Details.new(PathInfo.new(app_path, 10))
    details.technology = "python_flask"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = FlaskAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
