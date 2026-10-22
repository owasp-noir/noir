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
    instance.detect("project/routes/web.php", "<?php Route::get('/', function() {});").should be_true
  end

  it "detects Laravel from routes/api.php" do
    instance.detect("project/routes/api.php", "<?php Route::get('/api/users', [UserController::class, 'index']);").should be_true
  end

  # `routes/web.php` and `routes/api.php` are conventions Slim, plain PHP
  # and hand-rolled routers share. The filename used to be enough on its
  # own, which ran the whole Laravel analyzer over unrelated projects.
  it "does not detect Laravel from a route file with no Laravel symbol" do
    instance.detect("project/routes/web.php", %(<?php $app->get("/x", fn() => 1);)).should be_false
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

  # `artisan` reaches `detect` as a path, never as a bare basename, so the
  # old `filename == "artisan"` was unreachable — and `artisan` was not in
  # the `basenames:` gate either, so `detect` was not even dispatched on it.
  it "detects Laravel from artisan reached by path" do
    artisan_content = <<-PHP
      #!/usr/bin/env php
      <?php
      define('LARAVEL_START', microtime(true));
      require __DIR__.'/vendor/autoload.php';
      $status = (require_once __DIR__.'/bootstrap/app.php')->handleCommand($input);
      PHP
    instance.applicable?("project/artisan").should be_true
    instance.detect("project/artisan", artisan_content).should be_true
  end

  it "does not detect Laravel from an unrelated file named artisan" do
    instance.detect("project/artisan", "#!/bin/sh\necho artisan\n").should be_false
  end

  it "detects Laravel from Illuminate namespace usage" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Http\Controllers;
      use Illuminate\Http\Request;
      use Illuminate\Http\Response;

      class UserController extends Controller {}
      PHP
    instance.detect("project/app/Http/Controllers/UserController.php", controller_content).should be_true
  end

  it "detects Laravel from controller in app/Http/Controllers/" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Http\Controllers;

      class ProductController extends Controller {
        public function index() {}
      }
      PHP
    instance.detect("project/app/Http/Controllers/ProductController.php", controller_content).should be_true
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

  # Both layout branches match the scan-base-relative path: a checkout that
  # merely sits under an `app/Http/Controllers/` directory must not make
  # every PHP file in it look like a Laravel controller.
  it "scopes the layout branches to the scan base" do
    locator = CodeLocator.instance
    previous_bases = locator.scan_base_paths

    begin
      locator.scan_base_paths = ["/srv/myproj"]
      instance.detect("/srv/myproj/routes/web.php", "<?php Route::get('/', fn() => 1);").should be_true
      instance.detect("/srv/myproj/app/Http/Controllers/ThingController.php", "<?php class ThingController { }").should be_true

      locator.scan_base_paths = ["/srv/app/Http/Controllers/myproj"]
      instance.detect("/srv/app/Http/Controllers/myproj/ThingController.php", "<?php class ThingController { }").should be_false
    ensure
      locator.scan_base_paths = previous_bases
    end
  end

  it "does not detect Laravel from non-Laravel files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("admin.js", "console.log('not laravel')").should_not be_true
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should_not be_true
  end
end
