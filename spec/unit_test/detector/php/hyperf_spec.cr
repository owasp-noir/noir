require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Hyperf" do
  options = create_test_options
  instance = Detector::Php::Hyperf.new options

  it "detects Hyperf from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "hyperf/hyperf": "^3.1"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Hyperf from hyperf/http-server requirement" do
    composer_content = %({"require": {"hyperf/http-server": "^3.1"}})
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Hyperf from use statement" do
    php_content = "<?php\nuse Hyperf\\HttpServer\\Annotation\\Controller;\n"
    instance.detect("UserController.php", php_content).should be_true
  end

  it "detects Hyperf from Router reference" do
    php_content = "<?php\nuse Hyperf\\HttpServer\\Router\\Router;\nRouter::get('/x', $h);\n"
    instance.detect("config/routes.php", php_content).should be_true
  end

  it "does not detect Hyperf from unrelated PHP files" do
    instance.detect("index.php", "<?php echo 'hi';").should_not be_true
    instance.detect("composer.json", %({"require": {"slim/slim": "^4.12"}})).should_not be_true
  end
end
