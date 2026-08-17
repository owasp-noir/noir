require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect CakePHP" do
  options = create_test_options
  instance = Detector::Php::CakePHP.new options

  it "detects CakePHP from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": ">=8.1",
          "cakephp/cakephp": "^5.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects CakePHP from bin/cake console script" do
    cake_content = <<-'PHP'
      #!/usr/bin/php -q
      <?php
      require dirname(__DIR__) . '/vendor/autoload.php';
      require dirname(__DIR__) . '/config/bootstrap.php';
      exit((new Cake\Console\CommandRunner(new App\Application(dirname(__DIR__) . '/config')))->run($argv));
      PHP
    instance.detect("bin/cake", cake_content).should be_true
  end

  it "detects CakePHP from cake script" do
    cake_content = <<-PHP
      #!/usr/bin/php
      <?php
      // This is a dummy cake executable
      PHP
    instance.detect("cake", cake_content).should be_true
  end

  it "detects CakePHP from config/routes.php" do
    routes_content = <<-'PHP'
      <?php
      use Cake\Routing\RouteBuilder;
      $routes->scope('/', function (RouteBuilder $builder): void {
          $builder->connect('/', ['controller' => 'Pages', 'action' => 'display', 'home']);
      });
      PHP
    instance.detect("config/routes.php", routes_content).should be_true
  end

  it "does not detect CakePHP from unrelated cake file without Cake marker" do
    instance.detect("cake", "#!/bin/bash\necho hello").should be_false
  end

  it "does not detect CakePHP from non-CakePHP files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should be_false
    instance.detect("composer.json", %({"name": "app", "require": {"php": "^8.0"}})).should be_false
  end

  it "applicable? admits cake, composer.json, and PHP files" do
    instance.applicable?("cake").should be_true
    instance.applicable?("bin/cake").should be_true
    instance.applicable?("bin/cake.php").should be_true
    instance.applicable?("composer.json").should be_true
    instance.applicable?("config/routes.php").should be_true
    instance.applicable?("cake.py").should be_false
    instance.applicable?("app.rb").should be_false
  end
end
