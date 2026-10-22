require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

private def scan_summary(root : String) : Array(String)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  runner.detect
  runner.analyze
  runner.endpoints.map do |endpoint|
    params = endpoint.params.map { |param| "#{param.name}:#{param.param_type}" }.sort!.join(",")
    "#{endpoint.method} #{endpoint.url} #{endpoint.details.technology} [#{params}]"
  end.sort!
ensure
  CodeLocator.instance.reset_files
end

# Several walks build `Dir.glob` patterns from the project's own path, so
# a `[`, `{` or `*` in an ancestor directory name was read as glob syntax and
# silently matched nothing: Quarkus static resources, Android nav/string
# resources, JAX-RS derivative detection and JVM DTO imports all vanished.
describe "project paths containing glob metacharacters" do
  fixtures = File.expand_path("../../functional_test/fixtures", __DIR__)

  %w[java/quarkus java/jaxrs mobile/android java/spring].each do |fixture|
    it "scans #{fixture} the same under a bracketed parent directory" do
      root = File.tempname("noir-glob-metachar")
      begin
        plain = File.join(root, "plain", "app")
        bracketed = File.join(root, "proj [old] {a,b}", "app")
        [plain, bracketed].each do |dest|
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp_r(File.join(fixtures, fixture), dest)
        end

        expected = scan_summary(plain)
        expected.should_not be_empty
        scan_summary(bracketed).should eq(expected)
      ensure
        FileUtils.rm_rf(root) if root
      end
    end
  end
end
