require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Lumen" do
  options = create_test_options
  instance = Detector::Php::Lumen.new options

  it "detects Lumen from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "laravel/lumen-framework": "^10.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Lumen from bootstrap/app.php" do
    bootstrap_content = <<-PHP
      <?php
      $app = new Laravel\\Lumen\\Application(
        dirname(__DIR__)
      );
      PHP
    instance.detect("bootstrap/app.php", bootstrap_content).should be_true
  end

  it "detects Lumen from use Laravel\\Lumen namespace" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Http\Controllers;
      use Laravel\Lumen\Routing\Controller as BaseController;

      class UserController extends BaseController {}
      PHP
    instance.detect("app/Http/Controllers/UserController.php", controller_content).should be_true
  end

  it "does not detect Lumen from plain Laravel composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.0.2",
          "laravel/framework": "^10.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should_not be_true
  end

  it "does not detect Lumen from unrelated PHP files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("composer.json", %({"require": {"php": "^8.0"}})).should_not be_true
  end
end
