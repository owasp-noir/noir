require "../../func_spec.cr"

describe "--ai-context on Flask-AppBuilder views", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "names each @expose handler and reads its permission decorators" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/python/flask_appbuilder_auth/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    endpoints = app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep} }
    guards = endpoints.transform_values do |ep|
      ep.ai_context.try(&.guards.select(&.kind.==("auth_guard")).map(&.name)) || [] of String
    end

    endpoints["GET /api/v1/chart/export/"].handler.try(&.name).should eq("ChartRestApi.export")
    endpoints["GET /page/list/"].handler.try(&.name).should eq("PageView.list")

    # FAB's own CRUD routes and `@protect()` / `@has_access*`: a permission
    # check the Public role can open.
    guards["GET /api/v1/chart/"].should eq(["flask-appbuilder ModelRestApi protect (a setting can make it public)"])
    guards["GET /api/v1/chart/{pk}"].should eq(["flask-appbuilder ModelRestApi protect (a setting can make it public)"])
    guards["GET /api/v1/chart/export/"].should eq(["flask-appbuilder protect (a setting can make it public)"])
    # A comment line inside the stack does not end it.
    guards["GET /page/list/"].should eq(["flask-appbuilder has_access (a setting can make it public)"])
    # A project decorator answering through FAB's 401/403 helpers.
    guards["GET /api/v1/chart/favorite_status/"].should eq(["read_gate"])
    # A 401 in the `except` of the view call translates the view's error,
    # and `verify_jwt_in_request(optional=True)` refuses nobody.
    guards["POST /x/v1/query/"].should eq(["flask-appbuilder has_access_api (a setting can make it public)"])
    guards["GET /x/v1/ping/"].should be_empty
    guards["GET /api/v1/chart/public_info/"].should be_empty
    guards["GET /page/open/"].should be_empty
    # A handler that refuses an unidentified caller itself, past a feature
    # flag; a flag alone, or sending a logged-in caller away, is no guard.
    guards["GET /page/welcome/"].should eq(["handler refusing a caller who is not logged in"])
    guards["GET /page/flagged/"].should be_empty
    guards["GET /page/guest-only/"].should be_empty
    # A GET answered before the login check is open; the POST behind it is
    # not. A check only for POST leaves the GET-only route open.
    guards["GET /page/mixed/"].should be_empty
    guards["POST /page/mixed/"].should eq(["handler refusing a caller who is not logged in"])
    guards["GET /page/post-only-check/"].should be_empty
    # `verify_jwt_in_request(True)` is the optional form.
    guards["GET /page/jwt-positional/"].should be_empty
    # FAB's name means FAB's decorator only where the file imports
    # flask_appbuilder.
    guards["GET /plain/has-access"].should be_empty
  end
end
