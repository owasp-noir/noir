require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Laravel" do
  options = create_test_options
  instance = Detector::Php::Laravel.new options

  it "detects Laravel from composer.json" do
    composer_content = <<-JSON
      {
        "name": "laravel/laravel",
        "type": "project",
        "description": "The Laravel Framework.",
        "require": {
          "php": "^8.0.2",
          "laravel/framework": "^10.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Laravel from routes/web.php" do
    instance.detect("routes/web.php", "<?php Route::get('/', function() {});").should be_true
  end

  it "detects Laravel from routes/api.php" do
    instance.detect("routes/api.php", "<?php Route::get('/api/users', [UserController::class, 'index']);").should be_true
  end

  it "detects Laravel from bootstrap/app.php" do
    bootstrap_content = <<-PHP
      <?php
      $app = new Laravel\\Lumen\\Application(
        dirname(__DIR__)
      );
      PHP
    instance.detect("bootstrap/app.php", bootstrap_content).should be_true
  end

  it "detects Laravel from artisan command" do
    artisan_content = <<-PHP
      #!/usr/bin/env php
      <?php
      use Illuminate\\Foundation\\Application;
      require __DIR__.'/vendor/autoload.php';
      PHP
    instance.detect("artisan", artisan_content).should be_true
  end

  it "detects Laravel from Illuminate namespace usage" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Http\Controllers;
      use Illuminate\Http\Request;
      use Illuminate\Http\Response;

      class UserController extends Controller {}
      PHP
    instance.detect("app/Http/Controllers/UserController.php", controller_content).should be_true
  end

  it "detects Laravel from controller in app/Http/Controllers/" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Http\Controllers;

      class ProductController extends Controller {
        public function index() {}
      }
      PHP
    instance.detect("app/Http/Controllers/ProductController.php", controller_content).should be_true
  end

  it "detects Laravel from config/app.php" do
    config_content = <<-PHP
      <?php
      return [
        'name' => env('APP_NAME', 'Laravel'),
        'env' => env('APP_ENV', 'production'),
      ];
      PHP
    instance.detect("config/app.php", config_content).should be_true
  end

  it "does not detect Laravel from non-Laravel files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("admin.js", "console.log('not laravel')").should_not be_true
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should_not be_true
  end
end
