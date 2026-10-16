require "../../spec_helper"
require "../../../src/analyzer/engines/php_engine"

# A bare `Test` / `test` segment is a namespace, an app or a module id in
# real layouts, so it never marks a path as test source on its own. Only the
# per-module test trees that spell what they are do.
describe "PhpEngine.test_path? and a Test namespace" do
  it "keeps controllers and modules named Test/test" do
    [
      "/app/Http/Controllers/Test/QuizController.php",
      "/src/Controller/Test/ExamController.php",
      "/application/test/controller/Index.php",
      "/app/test/controller/Index.php",
      "/modules/test/controllers/DefaultController.php",
      "/app/Test/ExamService.php",
      "/routes/test.php",
      "/src/Test/Controller/Exam.php",
    ].each { |path| Analyzer::Php::PhpEngine.test_path?(path).should be_false }
  end

  it "still skips Magento test trees, PHPUnit dirs and test-env routes" do
    [
      "/app/code/Magento/Webapi/Test/Unit/_files/webapi.xml",
      "/app/code/Magento/Catalog/Test/Mftf/Test/AdminCreateProduct.xml",
      "/app/code/Magento/Catalog/Test/Integration/Block/ListTest.php",
      "/test/phpunit/Bootstrap.php",
      "/config/routes/test/routing.yaml",
      "/app/Http/Controllers/Tests/QuizController.php",
      "/tests/Feature/QuizTest.php",
      "/src/Controller/Test/ExamControllerTest.php",
    ].each { |path| Analyzer::Php::PhpEngine.test_path?(path).should be_true }
  end
end
