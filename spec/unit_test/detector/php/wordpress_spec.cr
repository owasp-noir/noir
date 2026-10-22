require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect WordPress" do
  options = create_test_options
  instance = Detector::Php::Wordpress.new options

  it "detects WordPress from composer.json plugin type" do
    composer_content = <<-JSON
      {
        "name": "acme/my-plugin",
        "type": "wordpress-plugin"
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects WordPress from a core bootstrap file" do
    instance.detect("wp-load.php", "<?php require dirname(__FILE__) . '/wp-config.php';").should be_true
  end

  # The `wp-content` branch matches on the *scan-base-relative* path, so it
  # needs a scan base registered to produce one. Passing a bare relative path
  # made this example depend on whatever `CodeLocator.scan_base_paths` some
  # earlier spec happened to leave behind: run this file on its own and it
  # failed, because with no base registered `base_relative` returns the path
  # untouched and `"wp-content/..."` has no leading slash to match.
  it "detects WordPress from wp-content path" do
    locator = CodeLocator.instance
    previous_bases = locator.scan_base_paths

    begin
      locator.scan_base_paths = ["/srv/site"]
      instance.detect("/srv/site/wp-content/plugins/foo/foo.php", "<?php // plugin code").should be_true

      # And the reason it matches the relative path rather than the absolute
      # one: a checkout that merely *lives under* a directory called
      # wp-content must not make every PHP file in it look like WordPress.
      locator.scan_base_paths = ["/wp-content/mysite"]
      instance.detect("/wp-content/mysite/app.php", "<?php // plain php").should be_false
    ensure
      locator.scan_base_paths = previous_bases
    end
  end

  it "detects WordPress from a plugin header" do
    plugin_content = <<-PHP
      <?php
      /**
       * Plugin Name: Cool Plugin
       */
      PHP
    instance.detect("cool-plugin.php", plugin_content).should be_true
  end

  it "detects WordPress from register_rest_route usage" do
    rest_content = <<-PHP
      <?php
      add_action('rest_api_init', function () {
        register_rest_route('myplugin/v1', '/books', array('methods' => 'GET'));
      });
      PHP
    instance.detect("includes/rest.php", rest_content).should be_true
  end

  it "detects WordPress from wp_ajax_ hook usage" do
    ajax_content = <<-PHP
      <?php
      add_action('wp_ajax_save_settings', 'save_settings');
      PHP
    instance.detect("plugin.php", ajax_content).should be_true
  end

  it "does not detect WordPress from plain PHP files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should_not be_true
  end

  it "does not detect WordPress from a Symfony route named admin_post_edit" do
    symfony_content = <<-'PHP'
      <?php
      namespace App\Controller;
      use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
      use Symfony\Component\Routing\Annotation\Route;
      class AdminController extends AbstractController {
          #[Route('/admin/post/edit', name: 'admin_post_edit')]
          public function edit(): Response {}
      }
      PHP
    instance.detect("src/Controller/AdminController.php", symfony_content).should_not be_true
  end
end
