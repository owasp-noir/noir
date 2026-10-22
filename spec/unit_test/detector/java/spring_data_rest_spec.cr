require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java Spring Data REST" do
  options = create_test_options
  instance = Detector::Java::SpringDataRest.new options

  it "pom.xml" do
    instance.detect("pom.xml", "<artifactId>spring-boot-starter-data-rest</artifactId>").should be_true
  end

  it "build.gradle" do
    instance.detect("build.gradle", "implementation 'org.springframework.data:spring-data-rest-webmvc'").should be_true
  end

  it "java import" do
    instance.detect("PersonRepository.java", "import org.springframework.data.rest.core.annotation.RepositoryRestResource;").should be_true
  end

  it "plain Spring Data JPA" do
    instance.detect("pom.xml", "<artifactId>spring-boot-starter-data-jpa</artifactId>").should be_false
    instance.detect("PersonRepository.java", "import org.springframework.data.repository.CrudRepository;").should be_false
  end

  it "non-pom xml" do
    instance.detect("notes.xml", "spring-boot-starter-data-rest").should be_false
  end
end
