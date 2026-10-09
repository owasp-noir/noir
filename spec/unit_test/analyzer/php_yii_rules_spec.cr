require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/yii"

describe "Analyzer::Php::Yii urlManager rules" do
  # The rules walk slices the source once per array-style rule; with
  # `String#[]` that is O(offset) on multi-byte text, so 20k rules carrying
  # CJK strings took minutes.
  it "stays linear on many array rules with multi-byte strings" do
    dir = File.tempname("noir_yii_rules")
    path = File.join(dir, "config/web.php")
    Dir.mkdir_p(File.dirname(path))
    rules = "['x' => '注释'],\n" * 20_000
    File.write(path, "<?php\nreturn ['components' => ['urlManager' => ['rules' => [\n#{rules}'GET,HEAD a' => 'b']]]];\n")

    begin
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Php::Yii.new(create_test_options).analyze_file(path) }
      endpoints.map { |e| "#{e.method} #{e.url}" }.sort!.should eq(["GET /a", "HEAD /a"])
      elapsed.should be < 2.seconds
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
