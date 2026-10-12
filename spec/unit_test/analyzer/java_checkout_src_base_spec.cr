require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# The JVM analyzers slice a file path at `/src/` (or `/src/main/java/`) to
# find its module root. Sliced on the absolute path, a checkout under
# `~/src/<project>` cut at the checkout directory instead: Helidon MP
# reported nothing and Quarkus lost its `application.properties` prefix.
private def scan_copy(fixture : String, root : String, ancestor : String) : Array(Endpoint)
  base = File.join(root, ancestor, File.basename(fixture))
  FileUtils.mkdir_p(File.dirname(base))
  FileUtils.cp_r(fixture, base)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints
ensure
  CodeLocator.instance.reset_files
end

describe "JVM module roots under a `src` checkout directory" do
  fixtures = "#{__DIR__}/../../functional_test/fixtures/java"

  {"src/proj", "src/main/java/proj"}.each do |ancestor|
    it "reports Helidon MP endpoints from a base under `#{ancestor}`" do
      root = File.tempname("noir-java-src-base")
      begin
        urls = scan_copy("#{fixtures}/helidon_mp", root, ancestor).map(&.url)
        urls.should contain("/greet/{name}")
      ensure
        FileUtils.rm_rf(root)
      end
    end

    it "keeps the Quarkus root-path from a base under `#{ancestor}`" do
      root = File.tempname("noir-java-src-base")
      begin
        urls = scan_copy("#{fixtures}/quarkus_kotlin", root, ancestor).map(&.url)
        urls.should contain("/svc/hello")
        urls.should_not contain("/hello")
      ensure
        FileUtils.rm_rf(root)
      end
    end
  end
end
