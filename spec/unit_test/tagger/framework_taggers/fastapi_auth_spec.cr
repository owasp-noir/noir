require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "FastAPIAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/python/fastapi_auth"
  main_path = "#{fixture_base}/main.py"

  # main.py line reference:
  # 18: @app.get("/public")
  # 19: async def public_page():
  # 23: @app.get("/profile")
  # 24: async def profile(current_user: User = Depends(get_current_user)):
  # 28: @app.get("/admin")
  # 29: async def admin(token: str = Security(oauth2_scheme)):
  # 33: @app.get("/open")
  # 34: async def open_page():

  it "detects Depends(get_current_user)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 24))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/profile", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("fastapi_auth")
    endpoint.tags[0].description.should contain("get_current_user")
  end

  it "detects Security(oauth2_scheme)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 29))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/admin", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("oauth2_scheme")
  end

  it "does not tag unprotected routes" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(main_path, 19))
    details.technology = "python_fastapi"
    endpoint = Endpoint.new("/public", "GET", [] of Param, details)

    tagger = FastAPIAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
