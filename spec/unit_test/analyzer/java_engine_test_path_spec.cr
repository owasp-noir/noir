require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

describe "Analyzer::Java::JavaEngine.test_path?" do
  it "flags the Maven/Gradle test source sets" do
    {"src/test", "src/it", "src/testFixtures", "src/jmh", "src/integrationTest", "src/functionalTest"}.each do |set|
      Analyzer::Java::JavaEngine.test_path?("/app/#{set}/java/a/FooController.java").should be_true
    end
  end

  it "flags JUnit classes by their Test.java / Tests.java suffix outside src/test" do
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/FooTest.java").should be_true
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/FooTests.java").should be_true
  end

  it "keeps real controllers, including names that only resemble the suffix" do
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/Latest.java").should be_false
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/TestParametersService.java").should be_false
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/UserController.java").should be_false
    Analyzer::Java::JavaEngine.test_path?("/x/src/main/java/a/FooTest.java/Bar.java").should be_false
  end
end
