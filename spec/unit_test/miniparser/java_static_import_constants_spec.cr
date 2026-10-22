require "spec"
require "../../../src/miniparsers/java_route_extractor_ts"

describe "Noir::TreeSitterJavaRouteExtractor static-import constants" do
  project_constants = {
    "Commons.ADMIN"                            => "/api/admin",
    "com.example.Commons.ADMIN"                => "/api/admin",
    "Commons.TASKS"                            => "/api/tasks",
    "com.example.Commons.TASKS"                => "/api/tasks",
    "com.example.Commons.Inner.DEEP"           => "/deep",
    "com.other.Commons.ADMIN"                  => "/other/admin",
    "com.example.OtherClass.NOT_IN_THE_IMPORT" => "/nope",
  }

  extract = ->(source : String) do
    constants = Hash(String, String).new
    Noir::TreeSitter.parse_java(source) do |root|
      constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source, project_constants)
    end
    constants
  end

  it "binds the bare name of `import static pkg.Class.NAME`" do
    constants = extract.call(<<-JAVA)
      package com.other.web;

      import static com.example.Commons.ADMIN;

      class OpsController {}
      JAVA

    constants["ADMIN"].should eq("/api/admin")
    constants.has_key?("TASKS").should be_false
  end

  it "binds every constant of `import static pkg.Class.*` under its bare name" do
    constants = extract.call(<<-JAVA)
      package com.other.web;

      import static com.example.Commons.*;

      class TaskController {}
      JAVA

    constants["ADMIN"].should eq("/api/admin")
    constants["TASKS"].should eq("/api/tasks")
    constants.has_key?("DEEP").should be_false
    constants.has_key?("NOT_IN_THE_IMPORT").should be_false
  end

  it "lets a local constant be defined from the imported bare name" do
    constants = extract.call(<<-JAVA)
      package com.other.web;

      import static com.example.Commons.ADMIN;

      class OpsController {
          private static final String BASE = ADMIN + "/ops";
      }
      JAVA

    constants["BASE"].should eq("/api/admin/ops")
  end

  it "resolves the class-level mapping that used to lose its whole prefix" do
    source = <<-JAVA
      package com.other.web;

      import static com.example.Commons.ADMIN;

      @RestController
      @RequestMapping(ADMIN + "/ops")
      class OpsController {
          @PostMapping("/raft")
          public void raft() {}
      }
      JAVA
    constants = extract.call(source)

    routes = [] of Noir::TreeSitterJavaRouteExtractor::Route
    Noir::TreeSitter.parse_java(source) do |root|
      routes = Noir::TreeSitterJavaRouteExtractor.extract_routes_from(root, source, constants: constants)
    end
    routes.map { |r| {r.verb, r.path} }.should eq([{"POST", "/api/admin/ops/raft"}])
  end

  it "ignores a static import that names no project constant" do
    constants = extract.call(<<-JAVA)
      import static org.springframework.web.servlet.function.RequestPredicates.*;
      import static com.example.Commons.MISSING;

      class Router {}
      JAVA

    constants.has_key?("MISSING").should be_false
    constants.has_key?("GET").should be_false
  end
end
