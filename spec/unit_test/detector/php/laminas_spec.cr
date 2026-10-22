require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Laminas" do
  options = create_test_options
  instance = Detector::Php::Laminas.new options

  it "detects Laminas MVC from composer.json" do
    composer_content = <<-JSON
      {
        "require": {
          "php": "^8.1",
          "laminas/laminas-mvc": "^3.7"
        }
      }
      JSON
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Mezzio from composer.lock" do
    lock_content = %({"packages": [{"name": "mezzio/mezzio"}]})
    instance.detect("composer.lock", lock_content).should be_true
  end

  it "detects legacy Zend Framework packages" do
    composer_content = %({"require": {"zendframework/zend-mvc": "^3.0"}})
    instance.detect("composer.json", composer_content).should be_true
  end

  it "detects Laminas namespaces from PHP files" do
    php_content = "<?php\nuse Laminas\\Router\\Http\\Segment;\n"
    instance.detect("module.config.php", php_content).should be_true
  end

  it "detects Mezzio namespaces from PHP files" do
    php_content = "<?php\nuse Mezzio\\Application;\n"
    instance.detect("public/index.php", php_content).should be_true
  end

  it "does not detect unrelated PHP projects" do
    instance.detect("index.php", "<?php echo 'Hello World';").should_not be_true
    instance.detect("composer.json", %({"require": {"slim/slim": "^4.12"}})).should_not be_true
  end

  it "does not detect non-routing Laminas/Zend transitive deps" do
    # PSR-7 / Swoole-adapter packages are pulled in transitively by countless
    # Laravel/Symfony/Yii apps; they must NOT trip the Laminas routing analyzer.
    instance.detect("composer.lock", %({"packages": [{"name": "zendframework/zend-diactoros"}]})).should_not be_true
    instance.detect("composer.lock", %({"packages": [{"name": "laminas/laminas-diactoros"}]})).should_not be_true
    instance.detect("composer.lock", %({"packages": [{"name": "mezzio/mezzio-swoole"}]})).should_not be_true
  end
end
