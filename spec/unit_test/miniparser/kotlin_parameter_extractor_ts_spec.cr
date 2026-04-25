require "spec"
require "../../../src/miniparsers/kotlin_parameter_extractor_ts"

private def extract(source : String,
                    class_name : String,
                    method_name : String,
                    verb : String,
                    parameter_format : String? = nil,
                    fields : Hash(String, Array(Noir::TreeSitterKotlinParameterExtractor::FieldInfo)) = {} of String => Array(Noir::TreeSitterKotlinParameterExtractor::FieldInfo))
  Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters(
    source, class_name, method_name, verb, parameter_format, fields
  )
end

describe Noir::TreeSitterKotlinParameterExtractor do
  describe "#extract_method_parameters" do
    it "treats @RequestParam as query and respects defaultValue" do
      source = <<-KT
        @RestController
        class C {
            @GetMapping("/x")
            fun get(@RequestParam(value = "q", defaultValue = "hello") q: String): String = ""
        }
        KT

      params = extract(source, "C", "get", "GET")
      params.map { |p| {p.name, p.value, p.param_type} }.should eq([
        {"q", "hello", "query"},
      ])
    end

    it "treats @RequestBody as json by default" do
      source = <<-KT
        class C {
            @PostMapping("/x")
            fun create(@RequestBody body: String): String = ""
        }
        KT

      params = extract(source, "C", "create", "POST")
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"body", "json"},
      ])
    end

    it "uses pre-detected consumes form for @RequestBody" do
      source = <<-KT
        class C {
            @PostMapping("/x", consumes = ["application/x-www-form-urlencoded"])
            fun create(@RequestBody body: String): String = ""
        }
        KT

      params = extract(source, "C", "create", "POST", parameter_format: "form")
      params.map(&.param_type).should eq(["form"])
    end

    it "skips @PathVariable parameters" do
      source = <<-KT
        class C {
            @GetMapping("/x/{id}")
            fun show(@PathVariable id: Long, @RequestParam q: String): String = ""
        }
        KT

      params = extract(source, "C", "show", "GET")
      params.map(&.name).should eq(["q"])
    end

    it "extracts @RequestHeader with name/value keyword arguments" do
      source = <<-KT
        class C {
            @GetMapping("/x")
            fun get(@RequestHeader(name = "X-Trace") trace: String): String = ""
        }
        KT

      params = extract(source, "C", "get", "GET")
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"X-Trace", "header"},
      ])
    end

    it "normalises HttpHeaders constants in @RequestHeader" do
      source = <<-KT
        class C {
            @GetMapping("/x")
            fun get(@RequestHeader(value = HttpHeaders.X_FORWARDED_FOR) ip: String): String = ""
        }
        KT

      params = extract(source, "C", "get", "GET")
      params.map(&.name).should eq(["X-Forwarded-For"])
    end

    it "exposes @CookieValue parameters as cookie params" do
      source = <<-KT
        class C {
            @GetMapping("/x")
            fun get(@CookieValue(name = "lorem", defaultValue = "ipsum") session: String): String = ""
        }
        KT

      params = extract(source, "C", "get", "GET")
      params.map { |p| {p.name, p.value, p.param_type} }.should eq([
        {"lorem", "ipsum", "cookie"},
      ])
    end

    it "expands DTO fields from a primary constructor data class" do
      dto = <<-KT
        package com.example

        data class Article(var title: String, var body: String, var slug: String = "draft")
        KT
      handler = <<-KT
        package com.example

        class C {
            @PostMapping("/x")
            fun create(@RequestBody article: Article): String = ""
        }
        KT

      fields = Noir::TreeSitterKotlinParameterExtractor.extract_class_fields(dto)
      params = extract(handler, "C", "create", "POST", fields: fields)
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"title", "json"},
        {"body", "json"},
        {"slug", "json"},
      ])
    end

    it "carries the parameter format across un-annotated trailing params" do
      source = <<-KT
        class C {
            @GetMapping("/x")
            fun get(@RequestParam q: String, page: Int): String = ""
        }
        KT

      params = extract(source, "C", "get", "GET")
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"q", "query"},
        {"page", "query"},
      ])
    end

    it "appends params= constraints with verb-aware dispatch" do
      query_source = <<-KT
        class C {
            @GetMapping("/x", params = ["api=v1", "!debug"])
            fun get(): String = ""
        }
        KT
      query_params = extract(query_source, "C", "get", "GET")
      query_params.map { |p| {p.name, p.value, p.param_type} }.should eq([
        {"api", "v1", "query"},
        {"debug", "", "query"},
      ])

      form_source = <<-KT
        class C {
            @PostMapping("/x", params = ["api=v1"])
            fun create(): String = ""
        }
        KT
      form_params = extract(form_source, "C", "create", "POST")
      form_params.map { |p| {p.name, p.param_type} }.should eq([
        {"api", "form"},
      ])
    end

    it "appends headers= constraints as header params" do
      source = <<-KT
        class C {
            @GetMapping("/x", headers = ["X-API-Version=1", "X-Trace"])
            fun get(): String = ""
        }
        KT
      params = extract(source, "C", "get", "GET")
      params.map { |p| {p.name, p.value, p.param_type} }.should eq([
        {"X-API-Version", "1", "header"},
        {"X-Trace", "", "header"},
      ])
    end
  end

  describe "#extract_consumes" do
    it "detects form via the urlencoded literal" do
      source = <<-KT
        class C {
            @PostMapping("/x", consumes = ["application/x-www-form-urlencoded"])
            fun create(): String = ""
        }
        KT
      Noir::TreeSitterKotlinParameterExtractor.extract_consumes(source, "C", "create").should eq("form")
    end

    it "detects json via APPLICATION_JSON_VALUE constant in arrayOf" do
      source = <<-KT
        class C {
            @PostMapping("/x", consumes = arrayOf(MediaType.APPLICATION_JSON_VALUE))
            fun create(): String = ""
        }
        KT
      Noir::TreeSitterKotlinParameterExtractor.extract_consumes(source, "C", "create").should eq("json")
    end

    it "returns nil when consumes is absent" do
      source = <<-KT
        class C {
            @PostMapping("/x")
            fun create(): String = ""
        }
        KT
      Noir::TreeSitterKotlinParameterExtractor.extract_consumes(source, "C", "create").should be_nil
    end
  end

  describe "#extract_class_fields" do
    it "collects primary constructor properties as fields" do
      source = <<-KT
        data class Article(var title: String, var body: String = "todo")
        KT
      fields = Noir::TreeSitterKotlinParameterExtractor.extract_class_fields(source)
      fields["Article"].map(&.name).should eq(["title", "body"])
      fields["Article"].map(&.init_value).should eq(["", "todo"])
    end

    it "collects class-body var/val properties" do
      source = <<-KT
        class User {
            var name: String = ""
            val email: String = ""
        }
        KT
      fields = Noir::TreeSitterKotlinParameterExtractor.extract_class_fields(source)
      fields["User"].map(&.name).sort!.should eq(["email", "name"])
    end
  end

  describe "#extract_package_name and #extract_imports" do
    it "reads the package and imports" do
      source = <<-KT
        package com.example.foo

        import com.example.bar.Baz
        import com.example.qux.*

        class X
        KT
      Noir::TreeSitterKotlinParameterExtractor.extract_package_name(source).should eq("com.example.foo")

      imports = Noir::TreeSitterKotlinParameterExtractor.extract_imports(source)
      imports.size.should eq(2)
      imports[0].path.should eq("com.example.bar.Baz")
      imports[0].wildcard?.should be_false
      imports[1].path.should eq("com.example.qux")
      imports[1].wildcard?.should be_true
    end
  end
end
