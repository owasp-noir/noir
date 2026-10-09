require "file_utils"
require "../../../../spec_helper"
require "../../../../../src/models/code_locator"
require "../../../../../src/analyzer/analyzers/javascript/nextjs"

# `exported_alias_for_method` ended on a `content.scan ... do` block, which
# returns the receiver, so a file with no `export { X as GET }` handed its
# whole source back as the "alias". The caller then compiled the entire
# file into a regex: wasted work on every Pages Router handler, and past
# PCRE2's pattern-size limit a raise that dropped the file's endpoints.
describe "Next.js Pages Router handler size" do
  it "keeps the endpoints of a large default-export handler" do
    temp_dir = File.tempname("noir_nextjs_large")
    api = File.join(temp_dir, "pages", "api")

    begin
      Dir.mkdir_p(api)
      file = File.join(api, "big.js")
      File.write(file, "export default function handler(req, res) {\n" +
                       "  if (req.method === 'POST') { res.json({}) }\n" +
                       "  // #{"x" * 80_000}\n}\n")

      locator = CodeLocator.instance
      locator.clear_all
      locator.register_file(file, File.read(file))

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = Analyzer::Javascript::Nextjs.new(options).analyze

      endpoints.map { |e| {e.method, e.url} }.should eq([{"POST", "/api/big"}])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
