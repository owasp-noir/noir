require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

describe "Analyzer::Java::JavaEngine::SPRING_BOOT_JAR_DISABLED_RE" do
  {
    %(bootJar { enabled = false })                                        => true,
    %(bootJar {\n    archiveClassifier = 'boot'\n    enabled = false\n})  => true,
    %(tasks.bootJar { enabled = false })                                  => true,
    %(tasks.named("bootJar") { enabled = false })                         => true,
    %(tasks.named<BootJar>("bootJar") {\n    enabled = false\n})          => true,
    %(tasks.getByName<BootJar>("bootJar") { isEnabled = false })          => true,
    %(bootJar.enabled = false)                                            => true,
    %(bootJar { enabled = true })                                         => false,
    %(jar { enabled = false })                                            => false,
    %(bootJar { mainClass = 'com.example.App' }\njar { enabled = false }) => false,
  }.each do |build, expected|
    it "reads #{build.lines.first} as #{expected}" do
      build.matches?(Analyzer::Java::JavaEngine::SPRING_BOOT_JAR_DISABLED_RE).should eq(expected)
    end
  end
end
