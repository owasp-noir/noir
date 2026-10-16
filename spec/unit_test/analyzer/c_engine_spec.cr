require "../../spec_helper"
require "../../../src/analyzer/engines/c_engine"

describe CEngine do
  describe ".test_path?" do
    it "matches a whole test, tests or unittest directory segment" do
      CEngine.test_path?("/test/test.cc").should be_true
      CEngine.test_path?("/tests/unittest.cpp").should be_true
      CEngine.test_path?("/lib/tests/integration_test/server/Foo.h").should be_true
      CEngine.test_path?("/unittest/public_server.c").should be_true
      CEngine.test_path?("/tests/unit_tests/test_mustache.cpp").should be_true
      CEngine.test_path?("/src/UnitTests/Foo.cpp").should be_true
    end

    # Directory segments only: a basename that merely contains "test" is
    # a real controller often enough (SpeedTest, latest_x).
    it "leaves production paths alone" do
      CEngine.test_path?("/src/app.cpp").should be_false
      CEngine.test_path?("/src/latest_x.cpp").should be_false
      CEngine.test_path?("/src/SpeedTestController.hpp").should be_false
      CEngine.test_path?("/src/contest/a.cpp").should be_false
      CEngine.test_path?("/src/attests/a.cpp").should be_false
      CEngine.test_path?("/example/server_test.cc").should be_false
    end
  end
end
