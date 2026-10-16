require "../../func_spec.cr"

# A controller under `modules/<id>/controllers` is routed through its module
# id (`admin/setting/basic`), nested modules chain ids, and subclasses of
# the built-in `yii\console\controllers\*` commands are CLI-only.
expected_endpoints = [
  Endpoint.new("/site/index", "GET"),
  Endpoint.new("/admin/setting/basic", "GET", [
    Param.new("tab", "", "query"),
  ]),
  Endpoint.new("/space/manage/member/index", "GET"),
  Endpoint.new("/item/list", "GET"),
]

tester = FunctionalTester.new("fixtures/php/yii_modules/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "drops the unprefixed module routes and console subclasses", tags: "functional" do
  urls = tester.app.endpoints.map(&.url)

  urls.should_not contain("/setting/basic")
  urls.should_not contain("/member/index")
  urls.should_not contain("/message/extract-module")
end
