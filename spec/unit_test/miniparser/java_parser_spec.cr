require "spec"
require "../../../src/miniparsers/java"

describe JavaParser do
  describe "get_package_name" do
    it "extracts package name from tokens" do
      lexer = JavaLexer.new
      tokens = lexer.tokenize("package com.example.app;\npublic class Foo {}")
      parser = JavaParser.new("/src/com/example/app/Foo.java", tokens)
      package = parser.get_package_name(parser.tokens)
      package.should eq("com.example.app")
    end

    it "returns empty string when no package declaration" do
      lexer = JavaLexer.new
      tokens = lexer.tokenize("public class Foo {}")
      parser = JavaParser.new("/Foo.java", tokens)
      package = parser.get_package_name(parser.tokens)
      package.should eq("")
    end
  end

  describe "get_root_source_directory" do
    it "resolves root directory based on package depth" do
      lexer = JavaLexer.new
      tokens = lexer.tokenize("public class Foo {}")
      parser = JavaParser.new("/src/Foo.java", tokens)
      root = parser.get_root_source_directory("/src/com/example/Foo.java", "com.example")
      root.should eq(Path.new("/src"))
    end

    it "handles single-level package" do
      lexer = JavaLexer.new
      tokens = lexer.tokenize("public class Foo {}")
      parser = JavaParser.new("/src/Foo.java", tokens)
      root = parser.get_root_source_directory("/src/app/Foo.java", "app")
      root.should eq(Path.new("/src"))
    end
  end

  describe "parse_import_statements" do
    it "parses simple import statements" do
      code = <<-JAVA
        package com.example;
        import java.util.List;
        import java.util.Map;
        public class Foo {}
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.import_statements.should contain("java.util.List")
      parser.import_statements.should contain("java.util.Map")
    end

    it "parses wildcard import" do
      code = <<-JAVA
        import java.util.*;
        public class Foo {}
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.import_statements.should contain("java.util.*")
    end

    it "parses static import" do
      code = <<-JAVA
        import static java.lang.Math.PI;
        public class Foo {}
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.import_statements.should contain("java.lang.Math.PI")
    end
  end

  describe "parse_classes" do
    it "parses a single class" do
      code = <<-JAVA
        public class MyClass {
          public void hello() {}
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/MyClass.java", tokens)
      parser.classes.size.should eq(1)
      parser.classes[0].name.should eq("MyClass")
    end

    it "parses interface" do
      code = <<-JAVA
        public interface MyInterface {
          void hello();
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/MyInterface.java", tokens)
      parser.classes.size.should eq(1)
      parser.classes[0].name.should eq("MyInterface")
    end
  end

  describe "parse_methods" do
    it "extracts methods from class" do
      code = <<-JAVA
        public class Foo {
          public void doSomething() {
            int x = 1;
          }
          public String getName() {
            return "foo";
          }
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.classes.size.should eq(1)
      methods = parser.classes[0].methods
      methods.has_key?("doSomething").should be_true
      methods.has_key?("getName").should be_true
    end

    it "parses method with throws clause" do
      code = <<-JAVA
        public class Foo {
          public void riskyMethod() throws Exception {
            throw new Exception();
          }
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.classes[0].methods.has_key?("riskyMethod").should be_true
    end

    it "parses interface method declarations" do
      code = <<-JAVA
        public interface Foo {
          void hello();
          String getName();
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.classes[0].methods.has_key?("hello").should be_true
      parser.classes[0].methods.has_key?("getName").should be_true
    end
  end

  describe "parse_fields" do
    it "extracts fields from class" do
      code = <<-JAVA
        public class Foo {
          private String name;
          public int age;
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      fields = parser.classes[0].fields
      fields.has_key?("name").should be_true
      fields["name"].access_modifier.should eq("private")
      fields["name"].type.should eq("String")
      fields.has_key?("age").should be_true
      fields["age"].access_modifier.should eq("public")
      fields["age"].type.should eq("int")
    end

    it "extracts static and final modifiers" do
      code = <<-JAVA
        public class Foo {
          private static final String CONSTANT = "value";
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      fields = parser.classes[0].fields
      fields.has_key?("CONSTANT").should be_true
      fields["CONSTANT"].is_static?.should be_true
      fields["CONSTANT"].is_final?.should be_true
      fields["CONSTANT"].init_value.should eq("\"value\"")
    end

    it "detects getter and setter methods" do
      code = <<-JAVA
        public class Foo {
          private String name;
          public String getName() {
            return name;
          }
          public void setName(String name) {
            this.name = name;
          }
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      fields = parser.classes[0].fields
      fields["name"].has_getter?.should be_true
      fields["name"].has_setter?.should be_true
    end
  end

  describe "parse_annotations_backwards" do
    it "parses simple annotation" do
      code = <<-JAVA
        @Deprecated
        public class Foo {
        }
        JAVA

      lexer = JavaLexer.new
      tokens = lexer.tokenize(code)
      parser = JavaParser.new("/Foo.java", tokens)
      parser.classes[0].annotations.has_key?("Deprecated").should be_true
    end
  end

  describe "FieldModel" do
    it "to_s includes field details" do
      field = FieldModel.new("private", true, true, "String", "CONSTANT", "hello")
      str = field.to_s
      str.should contain("private")
      str.should contain("static")
      str.should contain("final")
      str.should contain("String")
      str.should contain("CONSTANT")
      str.should contain("hello")
    end
  end
end
