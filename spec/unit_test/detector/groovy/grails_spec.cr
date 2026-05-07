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

  it "url_mappings_path" do
    instance.detect("project/grails-app/conf/UrlMappings.groovy", "class UrlMappings {}").should be_true
  end

  it "groovy_with_grails_import" do
    instance.detect("project/src/main/groovy/Foo.groovy", "import grails.gorm.transactions.Transactional").should be_true
  end

  it "non_groovy_file_outside_grails_app" do
    instance.detect("project/src/main/groovy/Foo.groovy", "println 'hi'").should be_false
  end
end
