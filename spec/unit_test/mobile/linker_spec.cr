require "../../spec_helper"
require "../../../src/models/logger"
require "../../../src/models/code_locator"
require "../../../src/mobile/linker.cr"

# The linker resolves an Android mobile endpoint's handler component to its
# source file, attaches the handler as a code_path, and pulls 1-hop callees
# from the intent-handling methods.
describe "NoirMobileLinker" do
  base = File.expand_path(File.join(__DIR__, "..", "..", "functional_test", "fixtures", "mobile", "android"))
  kt = File.join(base, "src", "main", "java", "com", "example", "myapp", "DeepLinkActivity.kt")

  logger = NoirLogger.new(false, false, false, true)

  # Seed the file_map so ClassIndex#build can find the .kt via files_by_extension.
  locator = CodeLocator.instance
  locator.clear("file_map")
  locator.register_file(kt, File.read(kt))

  # Endpoint is a struct; mutate locals directly (`.tap` would not persist).
  scheme = Endpoint.new("myapp://complex/:id", "GET")
  scheme.protocol = "mobile-scheme"
  scheme.metadata = {"via" => ".DeepLinkActivity", "package" => "com.example.myapp"}

  bare = Endpoint.new("myapp://accounts/profile", "GET")
  bare.protocol = "mobile-scheme"

  result = NoirMobileLinker.apply([scheme, bare], logger)
  linked = result[0]

  it "adds the handler source file as a code_path" do
    paths = linked.details.code_paths.map { |p| File.basename(p.path) }
    paths.should contain("DeepLinkActivity.kt")
  end

  it "extracts 1-hop callees from the intent handler" do
    names = linked.callees.map(&.name)
    names.should contain("webView.loadUrl")
    names.should contain("renderProfile")
  end

  it "leaves an endpoint whose component has no resolvable source untouched" do
    result[1].callees.should be_empty
  end
end
