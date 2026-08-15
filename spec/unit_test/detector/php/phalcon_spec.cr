require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Phalcon" do
  options = create_test_options
  instance = Detector::Php::Phalcon.new options

  it "detects Phalcon from ext-phalcon in composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": ">=8.0",
          "ext-phalcon": ">=5.0"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Phalcon from an auxiliary Composer package" do
    composer_content = %({"require-dev": {"phalcon/ide-stubs": "^5.0"}})
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Phalcon from php.ini extension declaration" do
    instance.detect("php.ini", "extension=phalcon.so").should be_true
    instance.detect("php.ini", "extension=phalcon").should be_true
  end

  it "detects Phalcon from a use statement" do
    php_content = "<?php\nuse Phalcon\\Mvc\\Micro;\n$app = new Micro();\n"
    instance.detect("index.php", php_content).should be_true
  end

  it "detects Phalcon from a fully-qualified class reference" do
    php_content = "<?php\n$app = new \\Phalcon\\Mvc\\Micro();\n"
    instance.detect("public/index.php", php_content).should be_true
  end

  it "detects Phalcon from a controller extending Phalcon\\Mvc\\Controller" do
    php_content = "<?php\nclass ProductsController extends \\Phalcon\\Mvc\\Controller {}\n"
    instance.detect("ProductsController.php", php_content).should be_true
  end

  it "does not detect Phalcon from unrelated PHP files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("controller.php", "<?php use Illuminate\\Http\\Request;").should_not be_true
    instance.detect("composer.json", %({"require": {"laravel/framework": "^10.0"}})).should_not be_true
    instance.detect("php.ini", "extension=redis.so").should_not be_true
  end
end
