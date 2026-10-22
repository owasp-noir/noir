require "../../spec_helper"
require "../../../src/analyzer/analyzers/dart/dart_helper"

describe Analyzer::Dart::Helper do
  describe ".test_path? test directories and templates" do
    it "flags test servers under tests/, testing/, test_utils/, test_driver/ and integration_test/" do
      [
        "/repo/tests/x.dart",
        "/repo/mono/tests/serverpod_test_server/lib/src/endpoints/a.dart",
        "/repo/lib/src/testing/server.dart",
        "/repo/integration_test/helpers/m.dart",
        "/repo/test_driver/m.dart",
        "/repo/lib/test_utils/s.dart",
      ].each { |path| Analyzer::Dart::Helper.test_path?(path, "/repo").should be_true }
    end

    it "flags Mason and Serverpod scaffold templates" do
      Analyzer::Dart::Helper.test_path?("/repo/bricks/x/__brick__/routes/index.dart", "/repo").should be_true
      Analyzer::Dart::Helper.test_path?("/repo/templates/{{#web}}web{{!web}}/routes/root.dart", "/repo").should be_true
    end

    it "matches whole directory segments only" do
      Analyzer::Dart::Helper.test_path?("/repo/lib/latest/index.dart", "/repo").should be_false
      Analyzer::Dart::Helper.test_path?("/repo/lib/contest/index.dart", "/repo").should be_false
      Analyzer::Dart::Helper.test_path?("/repo/lib/testing_app/index.dart", "/repo").should be_false
    end

    it "does not flag a scan base that itself lives under tests/ or a template path" do
      Analyzer::Dart::Helper.test_path?("/work/tests/app/lib/main.dart", "/work/tests/app").should be_false
      Analyzer::Dart::Helper.test_path?("/work/{{x}}/app/lib/main.dart", "/work/{{x}}/app").should be_false
    end
  end
end
