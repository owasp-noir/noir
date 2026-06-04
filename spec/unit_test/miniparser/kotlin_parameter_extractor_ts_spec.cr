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

    it "keeps @RequestBody json while an un-annotated command object on the same POST stays form" do
      fields = {
        "Dto"     => [Noir::TreeSitterKotlinParameterExtractor::FieldInfo.new("a", "public", true, "")],
        "Command" => [Noir::TreeSitterKotlinParameterExtractor::FieldInfo.new("b", "public", true, "")],
      }
      source = <<-KT
        @RestController
        class C {
            @PostMapping("/x")
            fun create(@RequestBody dto: Dto, command: Command): String = ""
        }
        KT
      # The analyzer passes consumes-only (nil here); the POST verb default
      # is applied per-parameter, so @RequestBody is json and the
      # un-annotated command object is form.
      params = extract(source, "C", "create", "POST", parameter_format: nil, fields: fields)
      params.map { |p| {p.name, p.param_type} }.should eq([
        {"a", "json"},
        {"b", "form"},
      ])
    end

    it "drops an @AuthenticationPrincipal / @CurrentUser injected parameter instead of expanding its DTO" do
      fields = {
        "SecurityUserItem" => [
          Noir::TreeSitterKotlinParameterExtractor::FieldInfo.new("userId", "public", true, ""),
          Noir::TreeSitterKotlinParameterExtractor::FieldInfo.new("role", "public", true, ""),
        ],
      }
      source = <<-KT
        @RestController
        class C {
            @PostMapping("/x")
            fun act(@CurrentUser user: SecurityUserItem): String = ""
        }
        KT
      extract(source, "C", "act", "POST", fields: fields).should be_empty
    end

    it "emits an @RequestParam collection parameter by name" do
      source = <<-KT
        @RestController
        class C {
            @GetMapping("/x")
            fun get(@RequestParam(name = "userIds") userIds: List<Long>): String = ""
        }
        KT
      extract(source, "C", "get", "GET").map { |p| {p.name, p.param_type} }.should eq([
        {"userIds", "query"},
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

    it "does not leak property annotation tokens into a field's init value" do
      source = <<-KT
        data class CreateUserRequest(
            @field:Schema(description = "User Name")
            @field:NotBlank(message = "field name is blank")
            val name: String,
            @field:Email
            val email: String,
        )
        KT
      fields = Noir::TreeSitterKotlinParameterExtractor.extract_class_fields(source)
      fields["CreateUserRequest"].map(&.name).should eq(["name", "email"])
      # The `@field:...` annotation source must not bleed into init_value.
      fields["CreateUserRequest"].map(&.init_value).should eq(["", ""])
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

    it "excludes computed properties (custom getter, no backing field)" do
      source = <<-KT
        class BaseEntity {
            var id: Int? = null
            val isNew: Boolean
                get() = this.id == null
            val inlineComputed: Int get() = 1
        }
        KT
      fields = Noir::TreeSitterKotlinParameterExtractor.extract_class_fields(source)
      # `id` is a stored field; `isNew` (sibling getter) and
      # `inlineComputed` (inline getter) are derived, not bindable.
      fields["BaseEntity"].map(&.name).should eq(["id"])
    end
  end

  describe "#extract_class_supertypes" do
    it "maps a class to its superCLASS (constructor-invoked supertype)" do
      source = <<-KT
        open class Person : BaseEntity() {
            var firstName = ""
        }
        class Owner : Person() {
            var address = ""
        }
        KT
      supers = Noir::TreeSitterKotlinParameterExtractor.extract_class_supertypes(source)
      supers["Owner"].should eq("Person")
      supers["Person"].should eq("BaseEntity")
    end

    it "ignores interface supertypes (no constructor invocation)" do
      source = <<-KT
        class Handler : Runnable, Serializable {
            var x = ""
        }
        KT
      Noir::TreeSitterKotlinParameterExtractor.extract_class_supertypes(source).has_key?("Handler").should be_false
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
