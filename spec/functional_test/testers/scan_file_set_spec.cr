require "../func_spec"
require "file_utils"

describe "scan file set", tags: "functional" do
  it "keeps URL hooks off excluded, pruned, and binary files" do
    root = File.tempname("noir-scan-file-set")
    begin
      FileUtils.mkdir_p(File.join(root, "node_modules"))
      File.write(File.join(root, "keep.txt"), "https://example.test/keep")
      File.write(File.join(root, "exclude.txt"), "https://example.test/excluded")
      File.write(File.join(root, "node_modules/module.txt"), "https://example.test/pruned")
      File.write(File.join(root, "build.o"), "https://example.test/object")
      File.write(File.join(root, "binary.dat"), "https://example.test/binary\n\0")

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(root)])
      options["exclude_path"] = YAML::Any.new("exclude.txt")
      options["url"] = YAML::Any.new("https://example.test")

      runner = NoirRunner.new(options)
      runner.detect
      runner.analyze
      runner.endpoints.map(&.url).should eq(["https://example.test/keep"])
      runner.endpoints.first.details.code_paths.map(&.path).should eq([File.join(root, "keep.txt")])
    ensure
      CodeLocator.instance.reset_files
      FileUtils.rm_rf(root)
    end
  end
end
