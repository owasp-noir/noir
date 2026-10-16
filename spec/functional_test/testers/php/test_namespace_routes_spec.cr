require "../../func_spec.cr"

# `Test` / `test` is a namespace, an app or a module id in these layouts, not
# a test directory: the exam feature's controllers are real routes. The
# plural `tests/` trees and Symfony's test-env routes beside them are not.
symfony_endpoints = [
  Endpoint.new("/exam", "GET", [
    Param.new("level", "", "query"),
  ]),
]

symfony = FunctionalTester.new("fixtures/php/test_namespace_symfony/", {
  :techs     => 2,
  :endpoints => symfony_endpoints.size,
}, symfony_endpoints)
symfony.perform_tests

yii_endpoints = [
  Endpoint.new("/test/exam/run", "GET", [
    Param.new("level", "", "query"),
  ]),
]

yii = FunctionalTester.new("fixtures/php/test_namespace_yii/", {
  :techs     => 2,
  :endpoints => yii_endpoints.size,
}, yii_endpoints)
yii.perform_tests

thinkphp_endpoints = [
  Endpoint.new("/test/index", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/test/index/index", "GET", [
    Param.new("id", "", "query"),
  ]),
]

thinkphp = FunctionalTester.new("fixtures/php/test_namespace_thinkphp/", {
  :techs     => 2,
  :endpoints => thinkphp_endpoints.size,
}, thinkphp_endpoints)
thinkphp.perform_tests

it "keeps tests/ trees and test-env routes out", tags: "functional" do
  symfony.app.endpoints.map(&.url).should_not contain("/exam-test-double")
  symfony.app.endpoints.map(&.url).should_not contain("/_test-env-only")
  yii.app.endpoints.map(&.url).should_not contain("/fake/double")
  thinkphp.app.endpoints.map(&.url).should_not contain("/double/index")
end
