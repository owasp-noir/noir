require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect CodeIgniter" do
  options = create_test_options
  instance = Detector::Php::CodeIgniter.new options

  it "detects CodeIgniter from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "codeigniter4/framework": "^4.4"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects CodeIgniter from spark CLI script" do
    spark_content = <<-PHP
      #!/usr/bin/env php
      <?php
      $paths = new Config\\Paths();
      require __DIR__ . '/vendor/autoload.php';
      PHP
    instance.detect("spark", spark_content).should be_true
  end

  it "detects CodeIgniter from app/Config/Routes.php" do
    routes_content = <<-'PHP'
      <?php
      use CodeIgniter\Router\RouteCollection;
      $routes->get('/', 'Home::index');
      PHP
    instance.detect("app/Config/Routes.php", routes_content).should be_true
  end

  it "detects CodeIgniter from CodeIgniter namespace usage" do
    controller_content = <<-'PHP'
      <?php
      namespace App\Controllers;
      use CodeIgniter\Controller;
      class Home extends BaseController {}
      PHP
    instance.detect("app/Controllers/Home.php", controller_content).should be_true
  end

  it "detects CodeIgniter 3 routes file" do
    ci3_content = <<-'PHP'
      <?php
      $route['default_controller'] = 'home';
      $route['products/(:num)'] = 'catalog/product_lookup_by_id/$1';
      PHP
    instance.detect("application/config/routes.php", ci3_content).should be_true
  end

  it "does not detect CodeIgniter from non-CodeIgniter files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should_not be_true
  end
end
