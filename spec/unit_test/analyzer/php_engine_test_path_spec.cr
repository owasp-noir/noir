require "../../spec_helper"
require "../../../src/analyzer/engines/php_engine"

describe "PhpEngine.test_path?" do
  it "treats test, fixture, Orchestra workbench and root docs trees as non-production" do
    [
      "/tests/Feature/Foo.php",
      "/src/Foo/Tests/Bar.php",
      "/app/code/Magento/Webapi/Test/Unit/_files/webapi.xml",
      "/test/phpunit/Bootstrap.php",
      "/src/Laravel/workbench/app/ApiResource/Home.php",
      "/src/Factory/Fixtures/SimpleComponent.php",
      "/legacy_tests/Browser/DuskCommand.php",
      "/config/routes/test/routing.yaml",
      "/docs/guides/declare-a-resource.php",
      "/src/FooTest.php",
      "/src/FooTests.php",
    ].each { |path| Analyzer::Php::PhpEngine.test_path?(path).should be_true }
  end

  it "leaves production paths that only resemble those names alone" do
    [
      "/src/Controller/Foo.php",
      "/resources/views/docs/[...slug].blade.php",
      "/lib/docs/page.php",
      "/docs.php",
      "/modules/custom/example/src/Controller/ExampleController.php",
      "/examples/demo.php",
      "/src/testing/Foo.php",
      "/src/Contest/Foo.php",
      "/src/workbenches/Foo.php",
      "/src/DataFixtures/Foo.php",
    ].each { |path| Analyzer::Php::PhpEngine.test_path?(path).should be_false }
  end
end
