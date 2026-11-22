require "../../spec_helper"
require "../../../src/analyzer/analyzers/java/spring"
require "../../../src/analyzer/analyzers/kotlin/spring"
require "../../../src/tagger/framework_taggers/java/spring_auth"

private def spring_annotation_rows(klass, files, &)
  dir = File.tempname("spring-route-annotations")
  locator = CodeLocator.instance
  locator.clear_all
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    locator.register_file(path, content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  rows = klass.new(options).analyze
  yield SpringAuthTagger.new(options).perform(rows).to_h { |ep| {ep.url, ep} }
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir
end

describe "Spring route annotation evidence" do
  it "puts a concrete override and its class ahead of the inherited mapping and resolves nested meta-annotations" do
    spring_annotation_rows(Analyzer::Java::Spring, {
      "Contract.java" => <<-JAVA,
        package app;
        import org.springframework.web.bind.annotation.*;
        @RolesAllowed("DEFAULT")
        interface Contract {
          @Secured("MEMBER") @GetMapping("/read") String read();
        }
        JAVA
      "Guards.java" => <<-JAVA,
        package app;
        @Staff @interface Supervisor {}
        @PreAuthorize(
          "hasRole('ADMIN')"
        ) @interface Staff {}
        JAVA
      "Web.java" => <<-JAVA,
        package app;
        import org.springframework.web.bind.annotation.*;
        @RestController @RequestMapping("/api") @Supervisor
        class Web implements Contract {
          @PermitAll public String read() { return ""; }
          @GetMapping("/write") String write() { return ""; }
        }
        JAVA
    }) do |rows|
      row = rows["/api/read"]
      evidence = row.details.code_paths.first.route_annotations.not_nil!
      guards = evidence.select { |ann| ann.name.in?("PermitAll", "PreAuthorize", "Secured", "RolesAllowed") }
      guards.map(&.origin).should eq([:method, :class, :inherited_method, :inherited_class])
      guards.map { |ann| {File.basename(ann.file), ann.line} }.should eq([{"Web.java", 5}, {"Guards.java", 3}, {"Contract.java", 5}, {"Contract.java", 3}])
      guards[1].composed_from.should eq("Supervisor")
      row.tags.map(&.name).should eq(["anonymous"])
      rows["/api/write"].tags.map(&.description).should eq(["Protected by Spring @PreAuthorize (@Supervisor) on the controller class"])
      row.to_json.should_not contain("Supervisor")
      row.to_yaml.should_not contain("Supervisor")
    end
  end

  it "binds Kotlin overloads and reads inherited guards from a superclass without a mapping" do
    spring_annotation_rows(Analyzer::Kotlin::Spring, {
      "Base.kt" => <<-KT,
        package app
        open class Base<T> {
          @Secured("STAFF")
          open fun fetch(id: String) = id
          @Secured("STAFF")
          open fun update(item: T) = item
        }
        KT
      "Web.kt" => <<-KT,
        package app
        import org.springframework.web.bind.annotation.*
        @RestController
        class Web : Base<String>() {
          @GetMapping("/string")
          override fun fetch(id: String) = id
          @GetMapping("/int")
          fun fetch(id: Int) = id
          @PostMapping("/generic")
          override fun update(item: String) = item
        }
        KT
    }) do |rows|
      guarded = rows["/string"]
      ann = guarded.details.code_paths.first.route_annotations.not_nil!.find!(&.name.==("Secured"))
      {ann.origin, File.basename(ann.file), ann.line}.should eq({:inherited_method, "Base.kt", 3})
      guarded.tags.map(&.description).should eq(["Protected by Spring @Secured"])
      rows["/int"].tags.should be_empty
      rows["/generic"].tags.map(&.name).should eq(["auth"])
      rows["/generic"].resolution.should eq({"guard" => Endpoint::RESOLUTION_HEURISTIC})
    end
  end

  it "judges recorded evidence even without a readable controller and distinguishes an empty binding" do
    dir = File.tempname("recorded-spring")
    path = File.join(dir, "Missing.java")
    location = PathInfo.new(path, 5)
    location.route_evidence = [RouteAnnotation.new("Secured", %("ROLE_ADMIN"), path, 4, :method)]
    options = create_test_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    tagger = SpringAuthTagger.new(options)
    endpoint = Endpoint.new("/admin", "GET", Details.new(location))
    tagger.perform([endpoint]).first.tags.map(&.name).should eq(["auth"])

    begin
      Dir.mkdir(dir)
      File.write(path, "class C {\n@Secured(\"ROLE_ADMIN\")\n@GetMapping\nString admin() {\nreturn \"\"; }\n}")
      CodeLocator.instance.register_path(path)
      location.route_evidence = [] of RouteAnnotation
      tagger.perform([Endpoint.new("/admin", "GET", Details.new(location))]).first.tags.should be_empty
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end
end
