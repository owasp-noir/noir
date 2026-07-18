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

  it "detects WordPress from wp-content path" do
    instance.detect("wp-content/plugins/foo/foo.php", "<?php // plugin code").should be_true
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
