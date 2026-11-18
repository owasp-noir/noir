require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# A JAX-RS sub-resource locator in a scanned resource pulls the routes of the
# class it returns out of that class's file. The lookup walked the import
# graph on disk, so a file the user excluded with `--exclude-path` still
# contributed its routes through a locator in a file they kept.
private def scan_jaxrs(root : String, exclude : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  options["exclude_path"] = YAML::Any.new(exclude)
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.select { |endpoint| endpoint.details.technology == "java_jaxrs" }
ensure
  CodeLocator.instance.reset_files
end

describe "JAX-RS sub-resources and --exclude-path" do
  it "does not report routes of an excluded sub-resource file" do
    root = File.tempname("noir-jaxrs-exclude")
    src = File.join(root, "src", "main", "java", "demo")

    begin
      FileUtils.mkdir_p(src)
      File.write(File.join(root, "pom.xml"), "<project><dependencies><dependency><groupId>jakarta.ws.rs</groupId><artifactId>jakarta.ws.rs-api</artifactId></dependency></dependencies></project>\n")
      File.write(File.join(src, "ItemsResource.java"), <<-JAVA)
        package demo;
        import jakarta.ws.rs.*;
        @Path("/items")
        public class ItemsResource {
          @GET public String list() { return ""; }
          @Path("/{id}/notes") public NotesResource notes() { return new NotesResource(); }
        }
        JAVA
      File.write(File.join(src, "NotesResource.java"), <<-JAVA)
        package demo;
        import jakarta.ws.rs.*;
        public class NotesResource {
          @GET public String get(@PathParam("id") String id) { return ""; }
        }
        JAVA

      scan_jaxrs(root, "").map { |endpoint| {endpoint.method, endpoint.url} }.should contain({"GET", "/items/{id}/notes"})

      endpoints = scan_jaxrs(root, "**/NotesResource.java")
      endpoints.map { |endpoint| {endpoint.method, endpoint.url} }.should eq([{"GET", "/items"}])
      endpoints.flat_map(&.details.code_paths).map(&.path).none?(&.ends_with?("NotesResource.java")).should be_true
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
    end
  end
end
