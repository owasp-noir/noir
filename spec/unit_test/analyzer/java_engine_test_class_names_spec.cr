require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

# The `Test.java` / `Tests.java` suffix rule of `JavaEngine.test_path?` needs a
# name before the suffix and covers `.kt` as well, since Javalin, Micronaut,
# Quarkus and JAX-RS read Kotlin sources through the same predicate.
describe "Analyzer::Java::JavaEngine.test_path? class-name suffix" do
  it "keeps a class literally named Test or Tests (a tutorial servlet is not a JUnit class)" do
    Analyzer::Java::JavaEngine.test_path?("src/main/java/tutorial/Test.java").should be_false
    Analyzer::Java::JavaEngine.test_path?("src/main/java/tutorial/Tests.java").should be_false
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/tutorial/Test.kt").should be_false
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/tutorial/Tests.kt").should be_false
  end

  it "applies the same suffix rule to Kotlin sources" do
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/com/example/FormBindingTest.kt").should be_true
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/com/example/SuiteTests.kt").should be_true
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/com/example/Latest.kt").should be_false
    Analyzer::Java::JavaEngine.test_path?("src/main/kotlin/com/example/TestSupport.kt").should be_false
  end

  it "still flags *Test.java and *Tests.java outside src/test" do
    Analyzer::Java::JavaEngine.test_path?("src/main/java/com/example/FormBindingTest.java").should be_true
    Analyzer::Java::JavaEngine.test_path?("src/main/java/com/example/SuiteTests.java").should be_true
    Analyzer::Java::JavaEngine.test_path?("src/main/java/com/example/FormBindingTest.java.bak").should be_false
  end
end
