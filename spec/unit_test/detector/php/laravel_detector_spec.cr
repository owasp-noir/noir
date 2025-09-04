require "../../../../src/detector/detectors/*"

describe "Detect Laravel" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Php::Laravel.new options

  it "detects Laravel from composer.json" do
    composer_content = %({
      "name": "laravel/laravel",
      "type": "project",
      "description": "The Laravel Framework.",
      "require": {
        "php": "^8.0.2",
        "laravel/framework": "^10.0"
      }
    })
    instance.detect("composer.json", composer_content).should eq(true)
  end

  it "detects Laravel from routes/web.php" do
    instance.detect("routes/web.php", "<?php Route::get('/', function() {});").should eq(true)
  end

  it "detects Laravel from routes/api.php" do
    instance.detect("routes/api.php", "<?php Route::get('/api/users', [UserController::class, 'index']);").should eq(true)
  end

  it "detects Laravel from bootstrap/app.php" do
    bootstrap_content = %{<?php
      $app = new Laravel\\Lumen\\Application(
        dirname(__DIR__)
      );
    }
    instance.detect("bootstrap/app.php", bootstrap_content).should eq(true)
  end

  it "detects Laravel from artisan command" do
    artisan_content = %(#!/usr/bin/env php
      <?php
      use Illuminate\\Foundation\\Application;
      require __DIR__.'/vendor/autoload.php';
    )
    instance.detect("artisan", artisan_content).should eq(true)
  end

  it "detects Laravel from Illuminate namespace usage" do
    controller_content = %{<?php
      namespace App\\Http\\Controllers;
      use Illuminate\\Http\\Request;
      use Illuminate\\Http\\Response;

      class UserController extends Controller {}
    }
    instance.detect("app/Http/Controllers/UserController.php", controller_content).should eq(true)
  end

  it "detects Laravel from controller in app/Http/Controllers/" do
    controller_content = %{<?php
      namespace App\\Http\\Controllers;

      class ProductController extends Controller {
        public function index() {}
      }
    }
    instance.detect("app/Http/Controllers/ProductController.php", controller_content).should eq(true)
  end

  it "detects Laravel from config/app.php" do
    config_content = %{<?php
      return [
        'name' => env('APP_NAME', 'Laravel'),
        'env' => env('APP_ENV', 'production'),
      ];
    }
    instance.detect("config/app.php", config_content).should eq(true)
  end

  it "does not detect Laravel from non-Laravel files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not eq(true)
    instance.detect("admin.js", "console.log('not laravel')").should_not eq(true)
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should_not eq(true)
  end
end
