require "../../spec_helper"
require "../../../src/models/logger"
require "../../../src/models/code_locator"
require "../../../src/mobile/linker.cr"
require "file_utils"

# The linker resolves an Android mobile endpoint's handler component to its
# source file, attaches the handler as a code_path, and pulls 1-hop callees
# from the intent-handling methods.
describe "NoirMobileLinker" do
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android"))
  kt = File.join(base, "src", "main", "java", "com", "example", "myapp", "DeepLinkActivity.kt")
  alias_kt = File.join(base, "src", "main", "java", "com", "example", "myapp", "AliasTargetActivity.kt")
  router_java = File.join(base, "src", "main", "java", "com", "example", "myapp", "RouterActivity.java")

  logger = NoirLogger.new(false, false, false, true)

  # Seed the file_map so ClassIndex#build can find the .kt via files_by_extension.
  locator = CodeLocator.instance
  locator.clear("file_map")
  locator.register_file(kt, File.read(kt))
  locator.register_file(alias_kt, File.read(alias_kt))
  locator.register_file(router_java, File.read(router_java))

  # Endpoint is a struct; mutate locals directly (`.tap` would not persist).
  scheme = Endpoint.new("myapp://complex/:id", "GET")
  scheme.protocol = "mobile-scheme"
  scheme.metadata = {"via" => ".DeepLinkActivity", "package" => "com.example.myapp"}

  bare = Endpoint.new("myapp://accounts/profile", "GET")
  bare.protocol = "mobile-scheme"

  alias_endpoint = Endpoint.new("myapp://alias", "GET")
  alias_endpoint.protocol = "mobile-scheme"
  alias_endpoint.metadata = {"via" => ".AliasTargetActivity", "package" => "com.example.myapp"}

  router_endpoint = Endpoint.new("myapp://router", "GET")
  router_endpoint.protocol = "mobile-scheme"
  router_endpoint.metadata = {"via" => ".RouterActivity", "package" => "com.example.myapp"}

  result = NoirMobileLinker.apply([scheme, bare, alias_endpoint, router_endpoint], logger)
  linked = result[0]
  linked_alias = result[2]
  linked_router = result[3]

  it "adds the handler source file as a code_path" do
    paths = linked.details.code_paths.map { |p| File.basename(p.path) }
    paths.should contain("DeepLinkActivity.kt")
  end

  it "extracts 1-hop callees from the intent handler" do
    names = linked.callees.map(&.name)
    names.should contain("webView.loadUrl")
    names.should contain("renderProfile")
  end

  it "extracts getQueryParameter reads as query params" do
    linked.params.any? { |p| p.name == "redirect" && p.param_type == "query" }.should be_true
    linked.params.any? { |p| p.name == "utm_source" && p.param_type == "query" }.should be_true
  end

  it "extracts get*Extra reads as extra params" do
    linked.params.any? { |p| p.name == "userId" && p.param_type == "extra" }.should be_true
    linked.params.any? { |p| p.name == "verified" && p.param_type == "extra" }.should be_true
  end

  it "leaves an endpoint whose component has no resolvable source untouched" do
    result[1].callees.should be_empty
  end

  it "links activity-alias endpoints to their target activity source" do
    linked_alias.callees.map(&.name).should contain("dispatchAlias")
    linked_alias.params.any? { |p| p.name == "aliasToken" && p.param_type == "extra" }.should be_true
  end

  it "expands Android delegate methods for extra params" do
    names = linked_router.callees.map(&.name)
    names.should contain("getInboundUrl")
    names.should contain("intent.getStringExtra")
    names.should_not contain("getString")
    linked_router.params.any? { |p| p.name == "EXTRA_TEXT" && p.param_type == "extra" }.should be_true
    linked_router.params.any? { |p| p.name == "EXTRA_STREAM" && p.param_type == "extra" }.should be_true
  end

  it "extracts Android params beyond the capped callee list" do
    root = File.tempname("noir-android-many-extras")

    begin
      source_dir = File.join(root, "src", "main", "java", "com", "example", "myapp")
      FileUtils.mkdir_p(source_dir)
      source = String.build do |io|
        io << "package com.example.myapp;\n"
        io << "import android.app.Activity;\n"
        io << "import android.content.Intent;\n"
        io << "import android.os.Bundle;\n"
        io << "class ManyExtrasActivity extends Activity {\n"
        io << "  protected void onCreate(Bundle savedInstanceState) {\n"
        12.times do |idx|
          io << "    Intent intent#{idx} = getIntent();\n"
          io << "    intent#{idx}.getStringExtra(\"extra#{idx}\");\n"
        end
        io << "  }\n"
        io << "}\n"
      end
      path = File.join(source_dir, "ManyExtrasActivity.java")
      File.write(path, source)

      locator.clear("file_map")
      locator.register_file(path, source)

      endpoint = Endpoint.new("myapp://many", "GET")
      endpoint.protocol = "mobile-scheme"
      endpoint.metadata = {"via" => ".ManyExtrasActivity", "package" => "com.example.myapp"}

      linked_many = NoirMobileLinker.apply([endpoint], logger)[0]

      linked_many.params.size.should eq(12)
      linked_many.params.map(&.name).should contain("extra11")
    ensure
      FileUtils.rm_rf(root) if Dir.exists?(root)
      locator.clear("file_map")
    end
  end
end
