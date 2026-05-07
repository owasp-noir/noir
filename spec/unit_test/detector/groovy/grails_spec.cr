require "../../../spec_helper"
require "../../../../src/detector/detectors/groovy/*"

describe "Detect Groovy Grails" do
  options = create_test_options
  instance = Detector::Groovy::Grails.new options

  it "build_gradle_with_grails_plugin" do
    content = <<-GRADLE
      plugins {
          id "org.grails.grails-web" version "6.1.0"
      }
      GRADLE
    instance.detect("build.gradle", content).should be_true
  end

  it "build_gradle_with_grails_dependency" do
    content = <<-GRADLE
      dependencies {
          implementation "org.grails:grails-core"
      }
      GRADLE
    instance.detect("build.gradle", content).should be_true
  end

  it "build_gradle_with_grails_plugins_namespace" do
    content = <<-GRADLE
      dependencies {
          implementation 'org.grails.plugins:spring-security-rest:3.0.0'
      }
      GRADLE
    instance.detect("build.gradle", content).should be_true
  end

  it "build_gradle_with_group_name_notation" do
    content = <<-GRADLE
      dependencies {
          implementation group: 'org.grails', name: 'grails-core', version: '5.0.0'
      }
      GRADLE
    instance.detect("build.gradle", content).should be_true
  end

  it "settings_gradle_with_grails_plugin_id" do
    content = <<-GRADLE
      pluginManagement {
          plugins {
              id 'org.grails.grails-web' version '5.0.0'
          }
      }
      GRADLE
    instance.detect("settings.gradle", content).should be_true
  end

  it "pom_xml_with_grails_dependency" do
    content = <<-XML
      <project>
        <dependencies>
          <dependency>
            <groupId>org.grails</groupId>
            <artifactId>grails-core</artifactId>
          </dependency>
        </dependencies>
      </project>
      XML
    instance.detect("pom.xml", content).should be_true
  end

  it "build_gradle_without_grails" do
    content = <<-GRADLE
      dependencies {
          implementation "org.springframework.boot:spring-boot-starter-web"
      }
      GRADLE
    instance.detect("build.gradle", content).should be_false
  end

  it "controller_path" do
    instance.detect("project/grails-app/controllers/BookController.groovy", "class BookController {}").should be_true
  end

  it "service_path" do
    instance.detect("project/grails-app/services/BookService.groovy", "class BookService {}").should be_true
  end

  it "url_mappings_path" do
    instance.detect("project/grails-app/conf/UrlMappings.groovy", "class UrlMappings {}").should be_true
  end

  it "gsp_view" do
    instance.detect("project/grails-app/views/index.gsp", "<h1>Hello</h1>").should be_true
  end

  it "groovy_with_grails_import" do
    instance.detect("project/src/main/groovy/Foo.groovy", "import grails.gorm.transactions.Transactional").should be_true
  end

  it "non_groovy_file_outside_grails_app" do
    instance.detect("project/src/main/groovy/Foo.groovy", "println 'hi'").should be_false
  end
end
