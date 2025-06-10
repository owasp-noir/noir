require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/javascript/koa"
require "../../../../src/models/analyzer"
require "../../../../src/models/endpoint"
require "../../../../src/models/param"

describe Analyzer::Javascript::Koa do
  it "analyzes koa files and extracts endpoints" do
    analyzer = Analyzer::Javascript::Koa.new("spec/support/fixtures/analyzer/javascript/koa_project", {"concurrency" => 1})
    endpoints = analyzer.analyze

    # Basic route: app.get('/simple', ...)
    simple_get = endpoints.find { |e| e.url == "/simple" && e.method == "GET" }
    simple_get.should_not be_nil
    simple_get.not_nil!.details.path_info.file_path.should contain "koa_project/app.js"

    # Route with path parameter: router.get('/users/:id', ...)
    user_by_id = endpoints.find { |e| e.url == "/users/:id" && e.method == "GET" }
    user_by_id.should_not be_nil
    user_by_id.not_nil!.params.any? { |p| p.name == "id" && p.param_type == "path" }.should be_true
    user_by_id.not_nil!.details.path_info.file_path.should contain "koa_project/routes/user_routes.js"

    # POST route: router.post('/users', ...)
    create_user = endpoints.find { |e| e.url == "/users" && e.method == "POST" }
    create_user.should_not be_nil
    create_user.not_nil!.details.path_info.file_path.should contain "koa_project/routes/user_routes.js"

    # Prefixed router: app.use('/api/v1', v1Router.routes()); v1Router.get('/status', ...)
    api_status = endpoints.find { |e| e.url == "/api/v1/status" && e.method == "GET" }
    api_status.should_not be_nil
    api_status.not_nil!.details.path_info.file_path.should contain "koa_project/routes/api_v1.js"

    # Another prefixed router: app.use(adminRouter.routes()) where adminRouter = new Router({ prefix: '/admin' })
    # adminRouter.get('/settings', ...)
    admin_settings = endpoints.find { |e| e.url == "/admin/settings" && e.method == "GET" }
    admin_settings.should_not be_nil
    admin_settings.not_nil!.details.path_info.file_path.should contain "koa_project/routes/admin_routes.js"

    # Route defined directly on app with prefix in use: app.use('/app_prefix', routerOnApp.routes()); routerOnApp.get('/info')
    app_prefix_info = endpoints.find { |e| e.url == "/app_prefix/info" && e.method == "GET" }
    app_prefix_info.should_not be_nil
    app_prefix_info.not_nil!.details.path_info.file_path.should contain "koa_project/routes/app_router.js"

    # Test .del as .delete
    delete_item = endpoints.find { |e| e.url == "/items/:itemId" && e.method == "DELETE" }
    delete_item.should_not be_nil
    delete_item.not_nil!.params.any? { |p| p.name == "itemId" && p.param_type == "path" }.should be_true
    delete_item.not_nil!.details.path_info.file_path.should contain "koa_project/app.js"

    # Test .all method
    all_method_route = endpoints.find { |e| e.url == "/everything" && e.method == "ALL" }
    all_method_route.should_not be_nil
    all_method_route.not_nil!.details.path_info.file_path.should contain "koa_project/app.js"

    # Ensure no duplicate endpoints if regex and parser find the same one (though typically parser runs first)
    # This is implicitly tested by the count if the fixture is well-defined.
    # Expected number of unique endpoints based on the fixture below.
    endpoints.size.should eq 8
  end
end
