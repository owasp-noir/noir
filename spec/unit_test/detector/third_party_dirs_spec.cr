require "file_utils"
require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/logger"

describe "detect_techs file walker" do
  # `third_party/` and `3rdparty/` hold vendored libraries (civetweb ships
  # Duktape's Node debugger UI there); the hyphenated and joined spellings are
  # ordinary first-party names (a WordPress `integrations/third-party/` module).
  # The pruning is scoped to native source trees (a CMake manifest here); see
  # third_party_dirs_scoping_spec.cr for the trees that keep their own.
  it "prunes third_party and 3rdparty directories but not third-party or thirdparty" do
    temp_dir = File.tempname("noir_detector_third_party")

    begin
      kept = [
        File.join(temp_dir, "app.js"),
        File.join(temp_dir, "src", "integrations", "third-party", "hook.js"),
        File.join(temp_dir, "src", "thirdparty", "hook.js"),
      ]
      pruned = [
        File.join(temp_dir, "third_party", "duktape", "debugger", "duk.js"),
        File.join(temp_dir, "src", "3rdparty", "lib", "server.js"),
      ]
      Dir.mkdir_p(temp_dir)
      File.write(File.join(temp_dir, "CMakeLists.txt"), "project(x)\n")
      (kept + pruned).each do |path|
        Dir.mkdir_p(File.dirname(path))
        File.write(path, "// x\n")
      end

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detect_techs([temp_dir], options, [] of PassiveScan, logger)
      files = locator.all_files

      kept.each { |path| files.should contain(path) }
      pruned.each { |path| files.should_not contain(path) }
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end

  # Only child entries are pruned: pointing `-b` at the directory itself still
  # scans it.
  it "still scans a third_party directory given as the scan base" do
    temp_dir = File.tempname("noir_detector_third_party_base")
    base = File.join(temp_dir, "third_party")

    begin
      file = File.join(base, "app.js")
      Dir.mkdir_p(base)
      File.write(file, "// x\n")

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(base)])
      logger = NoirLogger.new(false, false, false, true)
      locator = CodeLocator.instance
      locator.clear_all

      detect_techs([base], options, [] of PassiveScan, logger)

      locator.all_files.should contain(file)
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end
end
