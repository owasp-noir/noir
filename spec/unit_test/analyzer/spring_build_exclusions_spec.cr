require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

private alias JavaEngine = Analyzer::Java::JavaEngine

describe "Analyzer::Java::JavaEngine.gradle_excluded_everywhere?" do
  springdoc = JavaEngine::SPRING_SPRINGDOC_DEP_RE
  {
    %(configurations { all { exclude group: 'org.springdoc', module: 'springdoc-openapi-ui' } })                                                  => true,
    %(configurations {\n  compileOnly { extendsFrom annotationProcessor }\n  configureEach {\n    exclude module: 'springdoc-openapi-ui'\n  }\n}) => true,
    %(configurations.all {\n  exclude(group = "org.springdoc", module = "springdoc-openapi-starter-webmvc-ui")\n})                                => true,
    %(configurations.configureEach { exclude(module = "springdoc-openapi-ui") })                                                                  => true,
    %(configurations.all*.exclude group: 'org.springdoc', module: 'springdoc-openapi-ui')                                                         => true,
    # One configuration, a single dependency or another artifact: not everywhere.
    %(configurations { testImplementation { exclude module: 'springdoc-openapi-ui' } })                        => false,
    %(implementation('org.springdoc:springdoc-openapi-ui:1.7.0') { exclude group: 'org.yaml' })                => false,
    %(configurations.all { exclude group: 'org.springframework.boot', module: 'spring-boot-starter-logging' }) => false,
    %(configurations.all { exclude group: 'org.springdoc' })                                                   => false,
  }.each do |code, expected|
    it "reads #{code.lines.first} as #{expected}" do
      JavaEngine.gradle_excluded_everywhere?(code, springdoc).should eq(expected)
    end
  end
end
