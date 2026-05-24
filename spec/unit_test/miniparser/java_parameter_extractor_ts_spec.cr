require "../../spec_helper"
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
  end
end
