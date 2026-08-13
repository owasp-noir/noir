require "file_utils"
require "../../spec_helper"
require "../../../src/models/noir"

# The Java/Kotlin DTO field indexes are process-wide and keyed by absolute
# file path. That sharing is what keeps five Java analyzers from each
# re-parsing every DTO in the tree — but a path is only a stable key
# *within* one scan. Across scans the same path can hold different content,
# and neither index was registered with `ExtractionResultCache`, so
# `clear_all` at the top of `analysis_endpoints` did not reach them.
#
# Two scans of one path, in one process, with the DTO edited in between:
# before the fix the second scan reported the deleted field and missed the
# added one. The reachable production shape is a long-lived embedder — watch
# mode, or a CI daemon scanning one checkout across a `git pull`.
private def scan_param_names(root : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.flat_map { |endpoint| endpoint.params.map(&.name) }.sort!.uniq!
end

private def write_person_dto(root : String, field : String, getter : String)
  File.write(File.join(root, "src/main/java/com/example/PersonDto.java"), <<-JAVA)
    package com.example;

    public class PersonDto {
        private String name;
        private String #{field};

        public String getName() { return name; }
        public String get#{getter}() { return #{field}; }
    }
    JAVA
end

describe "DTO index scan lifecycle" do
  it "re-reads a DTO whose content changed between two scans of one path" do
    root = File.tempname("noir_dto_lifecycle")
    Dir.mkdir_p(File.join(root, "src/main/java/com/example"))

    begin
      File.write(File.join(root, "pom.xml"), <<-XML)
        <project><modelVersion>4.0.0</modelVersion>
          <groupId>com.example</groupId><artifactId>demo</artifactId><version>1.0</version>
          <dependencies><dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
          </dependency></dependencies>
        </project>
        XML
      File.write(File.join(root, "src/main/java/com/example/UserController.java"), <<-JAVA)
        package com.example;

        import org.springframework.web.bind.annotation.*;

        @RestController
        public class UserController {
            @PostMapping("/users")
            public String create(@RequestBody PersonDto person) {
                return "ok";
            }
        }
        JAVA

      write_person_dto(root, "email", "Email")
      first = scan_param_names(root)
      first.should contain("email")

      # Same path, different content — the shape a `git pull` produces
      # under a process that scans more than once.
      write_person_dto(root, "phone", "Phone")
      CodeLocator.instance.clear_all
      second = scan_param_names(root)

      second.should contain("phone")
      second.should_not contain("email")
    ensure
      FileUtils.rm_rf(root) if root
      CodeLocator.instance.clear_all
    end
  end
end
