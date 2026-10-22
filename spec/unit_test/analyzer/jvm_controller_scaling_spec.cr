require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/java/spring"
require "../../../src/analyzer/analyzers/groovy/grails"

# Large controllers used to cost quadratic time: Spring re-walked the whole
# tree per route to find its handler (and re-parsed an inherited `*Api`
# interface per route), Grails copied the rest of the class body for every
# top-level character. Both inputs below took tens of seconds; linear is ~1s.
private def scan_tree(files : Hash(String, String), & : YAML::Any -> Array(Endpoint)) : Tuple(Array(Endpoint), Time::Span)
  temp_dir = File.tempname("jvm_scaling")
  CodeLocator.instance.clear_all
  files.each do |relative, content|
    path = File.join(temp_dir, relative)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
    CodeLocator.instance.register_file(path, content)
  end
  endpoints = [] of Endpoint
  elapsed = Time.measure { endpoints = yield YAML::Any.new([YAML::Any.new(temp_dir)]) }
  {endpoints, elapsed}
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(temp_dir) if temp_dir
end

describe "JVM large-controller scaling" do
  it "matches delimiters from the open index, by char, on non-ASCII text" do
    code = %(한글 r.get("/(x)", c -> { é(); }); tail)
    open_idx = code.index!('(')
    close_idx = Analyzer::Java::JavaEngine.find_matching_delimiter(code, open_idx, '(', ')')
    close_idx.should eq(code.index!("); tail"))
    Analyzer::Java::JavaEngine.find_matching_delimiter(code, code.size - 1, '(', ')').should be_nil
  end

  it "scans a large Spring controller and inherited interface in linear time" do
    controller = String.build do |io|
      io << "package com.example;\n\nimport org.springframework.web.bind.annotation.*;\n\n"
      io << "@RestController\n@RequestMapping(\"/api\")\npublic class Big {\n"
      2000.times { |i| io << "    @GetMapping(\"/m#{i}\")\n    public String m#{i}(@RequestParam String q#{i}) { return \"x\"; }\n\n" }
      io << "}\n"
    end
    api = String.build do |io|
      io << "package com.example;\n\nimport org.springframework.web.bind.annotation.*;\n\n"
      io << "@RequestMapping(\"/inherited\")\npublic interface BigApi {\n"
      500.times { |i| io << "    @GetMapping(\"/i#{i}\")\n    String i#{i}(@RequestParam String p#{i});\n\n" }
      io << "}\n"
    end
    impl = String.build do |io|
      io << "package com.example;\n\nimport org.springframework.web.bind.annotation.*;\n\n@RestController\npublic class BigImpl implements BigApi {\n"
      500.times { |i| io << "    @Override\n    public String i#{i}(String p#{i}) { return \"x\"; }\n\n" }
      io << "}\n"
    end
    files = {
      "src/main/java/com/example/Big.java"     => controller,
      "src/main/java/com/example/BigApi.java"  => api,
      "src/main/java/com/example/BigImpl.java" => impl,
    }

    endpoints, elapsed = scan_tree(files) do |base|
      options = create_test_options
      options["base"] = base
      Analyzer::Java::Spring.new(options).analyze
    end

    endpoints.size.should eq(2500)
    endpoints.find! { |e| e.url == "/api/m1999" }.params.map(&.name).should eq(["q1999"])
    endpoints.find! { |e| e.url == "/inherited/i499" }.params.map(&.name).should eq(["p499"])
    elapsed.should be < 10.seconds
  end

  it "scans a Grails controller with a huge allowedMethods map in linear time" do
    controller = String.build do |io|
      io << "package demo\n\nclass BigController {\n    static allowedMethods = ["
      io << (0...4000).map { |i| "a#{i}: 'POST'" }.join(", ")
      io << "]\n\n"
      4000.times { |i| io << "    def a#{i}() { render params.x }\n" }
      io << "}\n"
    end

    endpoints, elapsed = scan_tree({"grails-app/controllers/demo/BigController.groovy" => controller}) do |base|
      options = create_test_options
      options["base"] = base
      Analyzer::Groovy::Grails.new(options).analyze
    end

    endpoints.size.should eq(4000)
    endpoints.last.url.should eq("/big/a3999")
    endpoints.last.details.code_paths.first.line.should eq(4005)
    elapsed.should be < 10.seconds
  end
end
