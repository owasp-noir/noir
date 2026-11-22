require "../../spec_helper"
require "../../../src/models/file_role"
require "../../../src/utils/path_scope"

describe Noir::FileRole do
  it "matches CLI conventions within the owning base, including a nested base named test" do
    bases = ["/work", "/work/test"]
    app = Noir::PathScope.base_relative("/work/test/src/main.dart", bases)
    suite = Noir::PathScope.base_relative("/work/test/TEST/main.dart", bases)
    Noir::FileRole.classify(app, Noir::FileRole::CLI_TEST).should eq(Noir::FileRole::Role::Production)
    Noir::FileRole.classify(suite, Noir::FileRole::CLI_TEST).should eq(Noir::FileRole::Role::Test)
  end

  it "keeps distinct CLI naming conventions" do
    path = "/commands/remote_SPEC.lua"
    Noir::FileRole.classify(path, Noir::FileRole::CLI_SPEC).test?.should be_true
    Noir::FileRole.classify(path, Noir::FileRole::CLI_TEST).production?.should be_true
  end

  it "requires both the filename and content when a convention needs evidence" do
    suite = Noir::FileRole::Convention.new(:test, name: /_test\.ts\z/, content: /Deno\.test/)
    Noir::FileRole.classify("/ab_test.ts", suite).production?.should be_true
    Noir::FileRole.classify("/ab_test.ts", suite, content: "router.get('/')").production?.should be_true
    Noir::FileRole.classify("/ab_test.ts/app.ts", suite, content: "Deno.test()").production?.should be_true
    Noir::FileRole.classify("/ab_test.ts", suite, content: "Deno.test()").test?.should be_true
  end

  it "returns the first applicable role when directories overlap" do
    vendor = Noir::FileRole::Convention.new(:vendored, path: %r{/vendor/})
    example = Noir::FileRole::Convention.new(:example, path: %r{/examples/})
    Noir::FileRole.classify("/vendor/examples/app.ts", vendor, example).vendored?.should be_true
    Noir::FileRole.classify("/examples/app.ts", vendor, example).example?.should be_true
  end
end
