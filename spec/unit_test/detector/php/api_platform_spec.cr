require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect API Platform" do
  options = create_test_options
  instance = Detector::Php::ApiPlatform.new options

  it "detects the composer package" do
    instance.detect("composer.json", %({"require": {"api-platform/core": "^3.2"}})).should be_true
    instance.detect("composer.json", %({"require": {"api-platform/laravel": "^4.1"}})).should be_true
  end

  it "detects an installed package in composer.lock but not an advisory conflict" do
    instance.detect("composer.lock", %({"packages": [{"name": "api-platform/core", "version": "v3.2.0"}]})).should be_true
    # roave/security-advisories lists api-platform/core under `conflict`.
    lock = %({"packages-dev": [{"name": "roave/security-advisories", "conflict": {"api-platform/core": "<3.4.17"}}]})
    instance.detect("composer.lock", lock).should be_false
  end

  it "detects an ApiPlatform\\Metadata import" do
    php = "<?php\nnamespace App\\Entity;\n\nuse ApiPlatform\\Metadata\\ApiResource;\n\n#[ApiResource]\nclass Book {}\n"
    instance.detect("src/Entity/Book.php", php).should be_true
  end

  it "does not detect unrelated PHP projects" do
    instance.detect("composer.json", %({"require": {"symfony/framework-bundle": "^7.0"}})).should be_false
    instance.detect("composer.json", %({"require": {"api-platform/core-extra": "^1.0"}})).should be_false
    instance.detect("src/Controller/Home.php", "<?php\n// see ApiPlatform\\Metadata\\ApiResource\nclass Home {}").should be_false
  end
end
