require "../../spec_helper"
require "file_utils"
require "../../../src/models/logger"
require "../../../src/miniparsers/java_parameter_extractor_ts"

describe Noir::TreeSitterJavaParameterExtractor do
  describe ".extract_package_name" do
    it "returns the dotted package name from a declaration" do
      source = <<-JAVA
        package com.example.api;
        class A {}
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_package_name(source).should eq("com.example.api")
    end

    it "returns the empty string when the file has no package declaration" do
      Noir::TreeSitterJavaParameterExtractor.extract_package_name("class A {}").should eq("")
    end
  end

  describe ".extract_imports" do
    it "returns each non-static import as an ImportDecl" do
      source = <<-JAVA
        package com.example;

        import com.example.dto.UserDto;
        import com.example.dto.OrderDto;
        JAVA

      imports = Noir::TreeSitterJavaParameterExtractor.extract_imports(source)
      paths = imports.map(&.path)
      paths.should contain("com.example.dto.UserDto")
      paths.should contain("com.example.dto.OrderDto")
      imports.none?(&.wildcard?).should be_true
    end

    it "flags star imports via wildcard?" do
      source = <<-JAVA
        package com.example;
        import com.example.dto.*;
        JAVA

      imports = Noir::TreeSitterJavaParameterExtractor.extract_imports(source)
      imports.size.should eq(1)
      imports.first.wildcard?.should be_true
      imports.first.path.should eq("com.example.dto")
    end

    it "skips `import static …` since static imports don't contribute DTOs" do
      source = <<-JAVA
        package com.example;
        import static org.springframework.web.bind.MyMath.PI;
        import com.example.dto.UserDto;
        JAVA

      imports = Noir::TreeSitterJavaParameterExtractor.extract_imports(source)
      imports.map(&.path).should eq(["com.example.dto.UserDto"])
    end
  end

  describe ".extract_class_fields" do
    it "captures public fields with their access modifier and setter status" do
      source = <<-JAVA
        class UserDto {
            public String name;
            private int age;
            public void setAge(int age) { this.age = age; }
        }
        JAVA

      fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["UserDto"]
      name = fields.find!(&.name.== "name")
      age = fields.find!(&.name.== "age")

      name.access_modifier.should eq("public")
      name.has_setter?.should be_false

      # `age` is private but has a setter → DTO expansion still picks
      # it up via setter detection.
      age.access_modifier.should eq("private")
      age.has_setter?.should be_true
    end

    it "captures initializer text for fields with default values" do
      source = <<-JAVA
        class UserDto {
            public String name = "default";
            public int age = 18;
        }
        JAVA

      fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["UserDto"]
      name_field = fields.find!(&.name.== "name")
      age_field = fields.find!(&.name.== "age")
      name_field.init_value.should contain("default")
      age_field.init_value.should eq("18")
    end

    it "omits classes that declare no fields" do
      source = <<-JAVA
        class Empty {
            public void method() {}
        }
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source).has_key?("Empty").should be_false
    end

    it "indexes multiple classes in the same file separately" do
      source = <<-JAVA
        class A { public String a; }
        class B { public int b; }
        JAVA

      results = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)
      results.keys.sort!.should eq(["A", "B"])
      results["A"].first.name.should eq("a")
      results["B"].first.name.should eq("b")
    end

    it "treats every field on a Lombok @Data class as setter-backed" do
      # Lombok synthesises the setters at compile time, so the source
      # has none — without special-casing the annotation a `@Data` DTO
      # would expand to zero body params.
      source = <<-JAVA
        import lombok.Data;
        @Data
        class PhotoRequest {
            private String title;
            private String url;
            private Long albumId;
        }
        JAVA

      fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["PhotoRequest"]
      fields.map(&.name).should eq(["title", "url", "albumId"])
      fields.all?(&.has_setter?).should be_true
    end

    it "recognises @Setter and @Value as field-binding annotations" do
      ["@Setter", "@Value"].each do |lombok_ann|
        source = lombok_ann + "\nclass Dto {\n    private String name;\n}\n"
        fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["Dto"]
        fields.find!(&.name.== "name").has_setter?.should be_true
      end
    end

    it "excludes static fields (constants are never request params)" do
      # `serialVersionUID` and `public static` config keys must not be
      # surfaced as body parameters, even on a Lombok @Data class where
      # every instance field becomes settable.
      source = <<-JAVA
        import lombok.Data;
        @Data
        class Category {
            private static final long serialVersionUID = 1L;
            public static final String TYPE = "category";
            private Long id;
            private String name;
        }
        JAVA

      fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["Category"]
      fields.map(&.name).should eq(["id", "name"])
    end
  end

  describe ".extract_consumes" do
    it "returns \"json\" for APPLICATION_JSON_VALUE" do
      source = <<-JAVA
        class C {
            @PostMapping(value = "/x", consumes = MediaType.APPLICATION_JSON_VALUE)
            public void m() {}
        }
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_consumes(source, "C", "m").should eq("json")
    end

    it "returns \"form\" for APPLICATION_FORM_URLENCODED_VALUE" do
      source = <<-JAVA
        class C {
            @PostMapping(value = "/x", consumes = MediaType.APPLICATION_FORM_URLENCODED_VALUE)
            public void m() {}
        }
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_consumes(source, "C", "m").should eq("form")
    end

    it "returns nil when no consumes attribute is set" do
      source = <<-JAVA
        class C {
            @PostMapping("/x")
            public void m() {}
        }
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_consumes(source, "C", "m").should be_nil
    end

    it "returns nil when the method isn't found" do
      source = "class C { public void m() {} }"
      Noir::TreeSitterJavaParameterExtractor.extract_consumes(source, "C", "missing").should be_nil
    end
  end

  describe ".extract_feign_client_classes" do
    it "captures every @FeignClient-annotated class/interface" do
      source = <<-JAVA
        @FeignClient(name = "users")
        interface UsersClient { @GetMapping("/u") String show(); }

        @FeignClient
        interface OrdersClient {}

        class Plain {}
        JAVA

      result = Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes(source)
      result.includes?("UsersClient").should be_true
      result.includes?("OrdersClient").should be_true
      result.includes?("Plain").should be_false
    end

    it "returns an empty set when no @FeignClient is present" do
      Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes(
        "class A {}"
      ).should be_empty
    end
  end

  describe ".extract_method_parameters" do
    it "picks up @RequestParam-annotated args as query params" do
      source = <<-JAVA
        class Controller {
            @GetMapping("/search")
            public String search(@RequestParam String q, @RequestParam int page) {
                return q;
            }
        }
        JAVA

      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "Controller", "search", "GET", nil,
        Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new
      )
      names = params.map(&.name).sort!
      names.should eq(["page", "q"])
      params.all? { |p| p.param_type == "query" }.should be_true
    end

    it "skips @PathVariable args (they're part of the URL pattern, not a query param)" do
      # Path variables are surfaced via the route URL (`/users/{id}`),
      # not the params list — legacy behaviour preserved so v0 output
      # stays stable across the tree-sitter rewrite.
      source = <<-JAVA
        class Controller {
            @GetMapping("/users/{id}")
            public String show(@PathVariable Long id) {
                return id.toString();
            }
        }
        JAVA

      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "Controller", "show", "GET", nil,
        Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new
      )
      params.should be_empty
    end

    it "picks up @RequestHeader-annotated args as header params" do
      source = <<-JAVA
        class Controller {
            @GetMapping("/x")
            public String show(@RequestHeader("X-Trace") String trace) {
                return trace;
            }
        }
        JAVA

      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "Controller", "show", "GET", nil,
        Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new
      )
      trace = params.find { |p| p.name == "X-Trace" || p.name == "trace" }
      trace.should_not be_nil
      trace.not_nil!.param_type.should eq("header")
    end

    it "returns an empty list when method not found" do
      source = "class C { public void m() {} }"
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "missing", "GET", nil,
        Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new
      )
      params.should be_empty
    end

    it "expands a Lombok @RequestBody DTO into one param per field" do
      # End-to-end: a `@Data` request DTO has no source-level setters,
      # yet every field must surface as a body param. Regression guard
      # for the common Spring shape where this previously yielded `[]`.
      dto_source = <<-JAVA
        import lombok.Data;
        @Data
        class PostRequest {
            private String title;
            private String body;
            private Long categoryId;
        }
        JAVA
      class_fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(dto_source)

      controller = <<-JAVA
        class PostController {
            @PostMapping("/posts")
            public String add(@RequestBody PostRequest req) { return ""; }
        }
        JAVA

      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        controller, "PostController", "add", "POST", "json", class_fields
      )
      params.map(&.name).should eq(["title", "body", "categoryId"])
      params.all? { |p| p.param_type == "json" }.should be_true
    end
  end

  describe "implicit (un-annotated) parameter binding" do
    empty_fields = Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new

    it "binds an un-annotated scalar on GET as a query param" do
      source = <<-JAVA
        class C {
            @GetMapping("/hr")
            public List<Hr> getAllHrs(String keywords) { return null; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "getAllHrs", "GET", nil, empty_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([{"keywords", "query"}])
    end

    it "binds an un-annotated wrapper-array on DELETE as a query param" do
      source = <<-JAVA
        class C {
            @DeleteMapping("/")
            public RespBean deleteByIds(Integer[] ids) { return null; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "deleteByIds", "DELETE", nil, empty_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([{"ids", "query"}])
    end

    it "binds an un-annotated scalar on POST as a form param" do
      source = <<-JAVA
        class C {
            @PostMapping("/login")
            public String login(String username, String password) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "login", "POST", nil, empty_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([{"username", "form"}, {"password", "form"}])
    end

    it "emits an annotated wrapper-array param (@RequestParam Integer[])" do
      source = <<-JAVA
        class C {
            @GetMapping("/x")
            public String x(@RequestParam Integer[] ids) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "x", "GET", nil, empty_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([{"ids", "query"}])
    end

    it "drops an @AuthenticationPrincipal command object instead of expanding its fields" do
      source = <<-JAVA
        class C {
            @PostMapping("/articles")
            public Object create(@RequestBody NewArticle a, @AuthenticationPrincipal User user) { return null; }
        }
        JAVA
      class_fields = {
        "NewArticle" => [Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("title", "private", true, "")],
        "User"       => [Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("password", "private", true, "")],
      }
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "create", "POST", nil, class_fields
      )
      params.map(&.name).should eq(["title"])
    end

    it "skips support objects supplied by path-only @ModelAttribute methods" do
      source = <<-JAVA
        @RequestMapping("/owners/{ownerId}")
        class PetController {
            @ModelAttribute("owner")
            public Owner findOwner(@PathVariable("ownerId") int ownerId) { return null; }

            @GetMapping("/pets/new")
            public String init(Owner owner, Model model) { return ""; }

            @PostMapping("/pets/new")
            public String create(Owner owner, @Valid Pet pet, BindingResult result) { return ""; }
        }
        JAVA
      class_fields = {
        "Owner" => [
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("firstName", "private", true, ""),
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("lastName", "private", true, ""),
        ],
        "Pet" => [
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("name", "private", true, ""),
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("birthDate", "private", true, ""),
        ],
      }

      get_params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "PetController", "init", "GET", nil, class_fields
      )
      get_params.should be_empty

      post_params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "PetController", "create", "POST", nil, class_fields
      )
      post_params.map { |p| {p.name, p.param_type} }.should eq([
        {"name", "form"},
        {"birthDate", "form"},
      ])
    end

    it "keeps optional @ModelAttribute form objects bindable" do
      source = <<-JAVA
        class OwnerController {
            @ModelAttribute("owner")
            public Owner findOwner(@PathVariable(name = "ownerId", required = false) Integer ownerId) { return null; }

            @GetMapping("/owners")
            public String search(@RequestParam(defaultValue = "1") int page, Owner owner, BindingResult result) { return ""; }
        }
        JAVA
      class_fields = {
        "Owner" => [
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("firstName", "private", true, ""),
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("lastName", "private", true, ""),
        ],
      }
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "OwnerController", "search", "GET", nil, class_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"page", "query"},
        {"firstName", "query"},
        {"lastName", "query"},
      ])
    end

    it "skips model.put support objects from @ModelAttribute supplier bodies" do
      source = <<-JAVA
        class VisitController {
            @ModelAttribute("visit")
            public Visit load(@PathVariable int ownerId, Map<String, Object> model) {
                Owner owner = owners.findById(ownerId).get();
                model.put("owner", owner);
                return new Visit();
            }

            @PostMapping("/visits")
            public String create(@ModelAttribute Owner owner, @Valid Visit visit, BindingResult result) { return ""; }
        }
        JAVA
      class_fields = {
        "Owner" => [
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("firstName", "private", true, ""),
        ],
        "Visit" => [
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("date", "private", true, ""),
          Noir::TreeSitterJavaParameterExtractor::FieldInfo.new("description", "private", true, ""),
        ],
      }
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "VisitController", "create", "POST", nil, class_fields
      )
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"date", "form"},
        {"description", "form"},
      ])
    end

    it "skips framework argument-resolver types not present in the DTO index" do
      source = <<-JAVA
        class C {
            @GetMapping("/")
            public String list(Pageable pageable, Model model, String q) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "list", "GET", nil, empty_fields
      )
      params.map(&.name).should eq(["q"])
    end
  end

  describe "@RequestBody field-visibility binding" do
    # A Lombok `@Getter`-only DTO has private fields and no setters.
    getter_dto = <<-JAVA
      class Body {
          private String email;
          private String password;
      }
      JAVA

    it "expands every field for a JSON @RequestBody even without setters" do
      class_fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(getter_dto)
      source = <<-JAVA
        class C {
            @PostMapping("/login")
            public String login(@RequestBody Body body) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "login", "POST", nil, class_fields
      )
      params.map { |p| {p.name, p.param_type} }.sort!.should eq([{"email", "json"}, {"password", "json"}])
    end

    it "keeps the setter/public gate for un-annotated form binding" do
      class_fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(getter_dto)
      source = <<-JAVA
        class C {
            @PostMapping("/login")
            public String login(Body body) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "login", "POST", nil, class_fields
      )
      params.should be_empty
    end
  end

  describe "record DTO components" do
    it "indexes record components as bindable fields" do
      source = <<-JAVA
        public record CreateArticle(String title, String description, int rank) {}
        JAVA
      fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(source)["CreateArticle"]
      fields.map(&.name).should eq(["title", "description", "rank"])
    end

    it "expands a record @RequestBody into its components" do
      record_src = <<-JAVA
        public record Body(String email, String password) {}
        JAVA
      class_fields = Noir::TreeSitterJavaParameterExtractor.extract_class_fields(record_src)
      source = <<-JAVA
        class C {
            @PostMapping("/login")
            public String login(@RequestBody Body body) { return ""; }
        }
        JAVA
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        source, "C", "login", "POST", nil, class_fields
      )
      params.map(&.name).sort!.should eq(["email", "password"])
    end
  end

  describe "overloaded handler disambiguation" do
    overloaded = <<-JAVA
      class VisitResource {
          @GetMapping("owners/*/pets/{petId}/visits")
          public List<Visit> read(@PathVariable int petId) { return null; }

          @GetMapping("pets/visits")
          public Visits read(@RequestParam List<Integer> petIds) { return null; }
      }
      JAVA

    empty_fields = Hash(String, Array(Noir::TreeSitterJavaParameterExtractor::FieldInfo)).new

    it "selects the overload whose body contains the route annotation line" do
      # The second `read` overload's @GetMapping is on line 5 (0-based 4).
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        overloaded, "VisitResource", "read", "GET", nil, empty_fields, 4
      )
      params.map(&.name).should eq(["petIds"])
    end

    it "falls back to the first overload without a line hint" do
      params = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters(
        overloaded, "VisitResource", "read", "GET", nil, empty_fields
      )
      # First `read` takes a @PathVariable, which is not emitted as a param.
      params.should be_empty
    end
  end

  describe ".extract_class_supertypes" do
    it "maps each class to its superclass simple name" do
      source = <<-JAVA
        class Owner extends Person {}
        class Person extends BaseEntity {}
        class BaseEntity {}
        class Standalone {}
        JAVA
      supers = Noir::TreeSitterJavaParameterExtractor.extract_class_supertypes(source)
      supers["Owner"].should eq("Person")
      supers["Person"].should eq("BaseEntity")
      supers.has_key?("BaseEntity").should be_false
      supers.has_key?("Standalone").should be_false
    end

    it "strips package qualifiers and generic arguments" do
      source = <<-JAVA
        class Page extends org.example.base.AbstractPage<Item> {}
        JAVA
      Noir::TreeSitterJavaParameterExtractor.extract_class_supertypes(source)["Page"].should eq("AbstractPage")
    end
  end

  describe "TreeSitterJavaDtoIndex cross-file inheritance" do
    it "merges inherited fields from a superclass defined in another package" do
      Noir::TreeSitterJavaDtoIndex.clear_cache!
      tmp = File.tempname("noir-dto-inherit")
      Dir.mkdir_p(File.join(tmp, "src/main/java/com/example/web"))
      Dir.mkdir_p(File.join(tmp, "src/main/java/com/example/model"))

      controller_path = File.join(tmp, "src/main/java/com/example/web/OwnerController.java")
      owner_path = File.join(tmp, "src/main/java/com/example/web/Owner.java")
      person_path = File.join(tmp, "src/main/java/com/example/model/Person.java")

      File.write(controller_path, <<-JAVA)
        package com.example.web;
        class OwnerController {
            public String create(Owner owner) { return ""; }
        }
        JAVA
      File.write(owner_path, <<-JAVA)
        package com.example.web;
        import com.example.model.Person;
        public class Owner extends Person {
            private String city;
            public String getCity() { return city; }
            public void setCity(String city) { this.city = city; }
        }
        JAVA
      File.write(person_path, <<-JAVA)
        package com.example.model;
        public class Person {
            private String firstName;
            private String lastName;
            public void setFirstName(String firstName) { this.firstName = firstName; }
            public void setLastName(String lastName) { this.lastName = lastName; }
        }
        JAVA

      controller_src = File.read(controller_path)
      index = Noir::TreeSitterJavaDtoIndex.new.build_for(controller_path, controller_src)
      index["Owner"]?.should_not be_nil
      index["Owner"].map(&.name).should eq(["city", "firstName", "lastName"])
    ensure
      FileUtils.rm_rf(tmp) if tmp
      Noir::TreeSitterJavaDtoIndex.clear_cache!
    end
  end
end
