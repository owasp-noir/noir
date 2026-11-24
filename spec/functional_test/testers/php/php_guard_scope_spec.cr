require "../../func_spec.cr"

# Requirements read only from the code that really guards the route.
describe "PHP guard scope", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  scan = ->(files : Hash(String, String)) do
    dir = File.tempname("php_guard_scope")
    files.each do |name, body|
      Dir.mkdir_p(File.dirname(File.join(dir, name)))
      File.write(File.join(dir, name), body)
    end
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    FileUtils.rm_rf(dir)
    app.endpoints
  end
  requires = ->(endpoints : Array(Endpoint), method : String, url : String) do
    Access.of(endpoints.find! { |e| e.method == method && e.url == url }).map(&.to_s)
  end

  it "reads a WordPress permission callback only from the class that declares it, and keeps handler checks" do
    endpoints = scan.call({"composer.json" => %({"type": "wordpress-plugin", "require": {"php": ">=7.4"}}), "wp-content/plugins/demo/demo.php" => <<-PHP})
      <?php
      /*
      Plugin Name: Demo
      */
      class Demo_Policy {
          public function check() { return current_user_can( 'manage_options' ); }
      }
      class Demo_Routes {
          public function register() {
              register_rest_route( 'demo/v1', '/other', array(
                  'methods' => 'GET', 'callback' => array( $this, 'other' ),
                  'permission_callback' => array( $this->policy, 'check' ),
              ) );
              register_rest_route( 'demo/v1', '/static', array(
                  'methods' => 'GET', 'callback' => array( $this, 'other' ),
                  'permission_callback' => 'Demo_Policy::check',
              ) );
              register_rest_route( 'demo/v1', '/own', array(
                  'methods' => 'GET', 'callback' => array( $this, 'other' ),
                  'permission_callback' => array( $this, 'check' ),
              ) );
          }
          public function check() { return is_user_logged_in(); }
          public function other() { return 1; }
      }
      add_action( 'wp_ajax_demo_admin', 'demo_admin' );
      function demo_admin() {
          if ( ! current_user_can( 'manage_options' ) ) { wp_die( -1, 403 ); }
          wp_send_json_success();
      }
      PHP
    requires.call(endpoints, "GET", "/wp-json/demo/v1/other").should eq(["authenticated", "unresolved"])
    requires.call(endpoints, "GET", "/wp-json/demo/v1/static").should eq(["authenticated", "unresolved"])
    requires.call(endpoints, "GET", "/wp-json/demo/v1/own").should eq(["authenticated"])
    requires.call(endpoints, "POST", "/wp-admin/admin-ajax.php?action=demo_admin").should eq(["authenticated", "unresolved"])
  end

  it "adds Drupal's _access: 'FALSE' to the route's other checks" do
    endpoints = scan.call({
      "composer.json"                        => %({"require": {"drupal/core-recommended": "^10.2"}}),
      "modules/custom/demo/demo.info.yml"    => "name: Demo\ntype: module\ncore_version_requirement: ^10\n",
      "modules/custom/demo/demo.routing.yml" => "demo.false:\n  path: '/d/false'\n  requirements:\n    _permission: 'a'\n    _access: 'FALSE'\n",
    })
    requires.call(endpoints, "GET", "/d/false").should eq(["(permission:a | unresolved)", "deny"])
  end
end
