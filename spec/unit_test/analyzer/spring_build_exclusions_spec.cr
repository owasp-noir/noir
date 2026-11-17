require "../../spec_helper"
require "../../../src/analyzer/engines/java_engine"

private alias JavaEngine = Analyzer::Java::JavaEngine

describe "Analyzer::Java::JavaEngine.gradle_excluded_modules" do
  ui = "springdoc-openapi-ui"
  {
    %(configurations { all { exclude group: 'org.springdoc', module: 'springdoc-openapi-ui' } })                                                  => [ui],
    %(configurations {\n  compileOnly { extendsFrom annotationProcessor }\n  configureEach {\n    exclude module: 'springdoc-openapi-ui'\n  }\n}) => [ui],
    %(configurations.all {\n  exclude(group = "org.springdoc", module = "springdoc-openapi-starter-webmvc-ui")\n})                                => ["springdoc-openapi-starter-webmvc-ui"],
    %(configurations.configureEach { exclude(module = "springdoc-openapi-ui") })                                                                  => [ui],
    %(configurations.all*.exclude group: 'org.springdoc', module: 'springdoc-openapi-ui')                                                         => [ui],
    # One configuration, a single dependency, or no module named: not everywhere.
    %(configurations { testImplementation { exclude module: 'springdoc-openapi-ui' } })           => [] of String,
    %(implementation('org.springdoc:springdoc-openapi-ui:1.7.0') { exclude module: 'snakeyaml' }) => [] of String,
    %(configurations.all { exclude group: 'org.springdoc' })                                      => [] of String,
  }.each do |code, expected|
    it "reads #{code.lines.first}" do
      JavaEngine.gradle_excluded_modules(code).to_a.sort.should eq(expected)
    end
  end
end

describe "Analyzer::Java::JavaEngine.mask_build_modules" do
  it "blanks only the coordinates of the excluded modules" do
    code = %(implementation 'org.springdoc:springdoc-openapi-ui:1.7.0'\nimplementation "org.springdoc:springdoc-openapi-starter-webmvc-ui"\n<artifactId>springdoc-openapi-ui</artifactId>)
    masked = JavaEngine.mask_build_modules(code, Set{"springdoc-openapi-ui"})
    masked.lines.size.should eq(3)
    masked.should_not contain("springdoc-openapi-ui:")
    masked.should_not contain("<artifactId>")
    masked.should contain("springdoc-openapi-starter-webmvc-ui")
  end
end

describe "Analyzer::Java::JavaEngine.gradle_own_build" do
  it "blanks the blocks that configure other modules, keeping lines" do
    code = <<-GRADLE
      dependencies { implementation 'a:b' }
      subprojects {
          bootJar { enabled = false }
      }
      project(':x') { configurations.all { exclude module: 'm' } }
      configure(subprojects.findAll { it.name != 'app' }) {
          bootJar { enabled = false }
      }
      dependencies { implementation project(':lib') }
      GRADLE
    own = JavaEngine.gradle_own_build(code)
    own.lines.size.should eq(code.lines.size)
    own.should contain("implementation 'a:b'")
    own.should contain("implementation project(':lib')")
    own.should_not contain("bootJar")
    own.should_not contain("exclude")
  end
end
