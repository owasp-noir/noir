require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Drupal" do
  options = create_test_options
  instance = Detector::Php::Drupal.new options

  it "detects Drupal from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "drupal/core-recommended": "^10.2"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Drupal from a *.routing.yml file" do
    routing_content = <<-'YAML'
      example.list:
        path: '/example'
        defaults:
          _controller: '\Drupal\example\Controller\ExampleController::listing'
      YAML
    instance.detect("web/modules/custom/example/example.routing.yml", routing_content).should be_true
  end

  it "detects Drupal from a module *.info.yml file" do
    info_content = <<-YAML
      name: Example
      type: module
      core_version_requirement: ^10
      YAML
    instance.detect("example.info.yml", info_content).should be_true
  end

  it "detects Drupal from a .module file" do
    instance.detect("example.module", "<?php\nfunction example_help() {}").should be_true
  end

  it "detects Drupal from the Drupal namespace in PHP" do
    controller_content = <<-'PHP'
      <?php
      namespace Drupal\example\Controller;
      use Drupal\Core\Controller\ControllerBase;
      class ExampleController extends ControllerBase {}
      PHP
    instance.detect("src/Controller/ExampleController.php", controller_content).should be_true
  end

  it "does not detect Drupal from unrelated files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("services.yml", "services:\n  foo.bar:\n    class: Foo").should_not be_true
    instance.detect("composer.json", %({"require": {"symfony/framework-bundle": "^6.0"}})).should_not be_true
  end

  it "does not detect Drupal from non-PHP files that merely share an extension" do
    # Heroku-style shell .profile
    instance.detect(".profile", "export PATH=$PATH:/usr/local/bin\nalias ll='ls -la'").should_not be_true
    # freedesktop INI index.theme
    instance.detect("index.theme", "[Icon Theme]\nName=Hicolor\nDirectories=16x16").should_not be_true
  end
end
