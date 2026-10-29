require "../../func_spec.cr"

# #3315: WordPress `$this->namespace` set in the constructor and resolved per
# class; `permission_callback` and `wp_ajax_` (without `nopriv_`) as guards;
# Drupal `#[Route]` attributes and `requirements` access checks.
describe "WordPress / Drupal routes and guards", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(fixture : String) do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/#{fixture}/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    app.endpoints
  end
  guards = ->(endpoints : Array(Endpoint), method : String, url : String) do
    ep = endpoints.find! { |e| e.method == method && e.url == url }
    ep.ai_context.try(&.guards.map(&.name)) || [] of String
  end

  it "resolves constructor-set REST namespaces per class and reads permission callbacks" do
    endpoints = scan.call("wordpress_rest_guards")
    endpoints.map { |e| "#{e.method} #{e.url}" }.sort!.should eq([
      "GET /wp-admin/admin-ajax.php?action=demo_lookup",
      "GET /wp-admin/admin-ajax.php?action=demo_save",
      "GET /wp-admin/admin-ajax.php?action=demo_split",
      "GET /wp-json/demo/v1/children",
      "GET /wp-json/demo/v1/children/feed",
      "GET /wp-json/demo/v1/me",
      "GET /wp-json/wp/v2/settings",
      "POST /wp-admin/admin-ajax.php?action=demo_lookup",
      "POST /wp-admin/admin-ajax.php?action=demo_save",
      "POST /wp-admin/admin-ajax.php?action=demo_split",
      "POST /wp-json/demo/v1/items",
      "POST /wp-json/wp/v2/settings",
    ])
    guards.call(endpoints, "GET", "/wp-json/wp/v2/settings").should eq(["WordPress permission_callback current_user_can('manage_options')"])
    guards.call(endpoints, "POST", "/wp-json/wp/v2/settings").should be_empty
    guards.call(endpoints, "POST", "/wp-json/demo/v1/items").should eq(["WordPress permission_callback current_user_can('edit_posts')"])
    guards.call(endpoints, "GET", "/wp-json/demo/v1/me").should eq(["WordPress permission_callback login check"])
    guards.call(endpoints, "POST", "/wp-admin/admin-ajax.php?action=demo_save").should_not be_empty
    guards.call(endpoints, "POST", "/wp-admin/admin-ajax.php?action=demo_lookup").should be_empty
    # `nopriv_` registered from another file still makes the action public.
    guards.call(endpoints, "POST", "/wp-admin/admin-ajax.php?action=demo_split").should be_empty
    # Another class's same-named method is not this route's callback.
    guards.call(endpoints, "GET", "/wp-json/demo/v1/children").should be_empty
    # A capability checked only under a further condition leaves the route open.
    guards.call(endpoints, "GET", "/wp-json/demo/v1/children/feed").should be_empty
  end

  it "reads Drupal #[Route] attributes and requirements" do
    endpoints = scan.call("drupal_attr_guards")
    guards.call(endpoints, "GET", "/admin/demo").should eq(["Drupal _permission (administer site configuration)"])
    guards.call(endpoints, "GET", "/demo/mine").should eq(["Drupal _user_is_logged_in"])
    guards.call(endpoints, "GET", "/demo/open").should be_empty
    guards.call(endpoints, "POST", "/demo/login").should be_empty
    guards.call(endpoints, "GET", "/demo/reset/{uid}").should be_empty
    guards.call(endpoints, "GET", "/demo/{node}/edit").should eq(["Drupal _entity_access (node.update)"])
    guards.call(endpoints, "GET", "/demo/register").should be_empty
    guards.call(endpoints, "GET", "/demo/either").should be_empty
    endpoints.none?(&.url.==("/demo-prefix")).should be_true
  end
end
