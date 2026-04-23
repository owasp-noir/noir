require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Slim" do
  options = create_test_options
  instance = Detector::Php::Slim.new options

  it "detects Slim from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "slim/slim": "^4.12"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Slim from use statement" do
    php_content = "<?php\nuse Slim\\Factory\\AppFactory;\n$app = AppFactory::create();\n"
    instance.detect("index.php", php_content).should be_true
  end

  it "detects Slim from AppFactory reference" do
    php_content = "<?php\n$app = Slim\\Factory\\AppFactory::create();\n"
    instance.detect("public/index.php", php_content).should be_true
  end

  it "detects Slim from SlimFramework marker" do
    instance.detect("bootstrap.php", "<?php // SlimFramework bootstrap").should be_true
  end

  it "does not detect Slim from unrelated PHP files" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("controller.php", "<?php use Illuminate\\Http\\Request;").should_not be_true
    instance.detect("composer.json", %({"require": {"laravel/framework": "^10.0"}})).should_not be_true
  end
end
