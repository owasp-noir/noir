require "file_utils"
require "../../spec_helper"
require "../../../src/detector/detector"
require "../../../src/models/analyzer"
require "../../../src/models/code_locator"
require "../../../src/models/logger"

# `third_party/` is vendored source only in a native (C/C++/Bazel/GN) tree; in
# a language app it is an ordinary directory name that can hold real routes.
# Each layout maps relative file paths to whether the walk must keep them.
private def walked_files(layout : Hash(String, Bool))
  temp_dir = File.tempname("noir_detector_third_party_scope")
  begin
    layout.each_key do |rel|
      path = File.join(temp_dir, rel)
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
    layout.each do |rel, kept|
      fail "#{rel}: expected kept=#{kept}" unless files.includes?(File.join(temp_dir, rel)) == kept
    end
  ensure
    FileUtils.rm_rf(temp_dir) if temp_dir
    CodeLocator.instance.clear_all
  end
end

describe "detect_techs third_party scoping" do
  it "keeps third_party routes in Python, JS and Next.js app trees" do
    walked_files({
      "requirements.txt"                      => true,
      "app/third_party/routes.py"             => true,
      "web/package.json"                      => true,
      "web/pages/api/third_party/callback.ts" => true,
      "web/app/api/third_party/route.ts"      => true,
      "web/src/routes/3rdparty/webhooks.js"   => true,
    })
  end

  it "keeps third_party in an app that merely uses submodules or DEPS" do
    walked_files({
      ".gitmodules"          => true,
      "package.json"         => true,
      "third_party/hooks.js" => true,
      "DEPS"                 => true,
      "sub/DEPS"             => true,
      "sub/package.json"     => true,
      "sub/3rdparty/hook.js" => true,
    })
  end

  it "prunes third_party under CMake, Bazel, GN and submodule-only roots" do
    walked_files({
      "cmake/CMakeLists.txt"                   => true,
      "cmake/third_party/duktape/debug.js"     => false,
      "bazel/WORKSPACE"                        => true,
      "bazel/src/third_party/duktape/debug.js" => false,
      "chromium/DEPS"                          => true,
      "chromium/BUILD.gn"                      => true,
      "chromium/3rdparty/duktape/debug.js"     => false,
      "mods/.gitmodules"                       => true,
      "mods/third_party/duktape/debug.js"      => false,
      "pyext/CMakeLists.txt"                   => true,
      "pyext/pyproject.toml"                   => true,
      "pyext/third_party/pybind/server.js"     => false,
    })
  end

  it "scopes a nested app inside a native tree by its own manifest" do
    walked_files({
      "CMakeLists.txt"                 => true,
      "tools/third_party/lib/debug.js" => false,
      "web/package.json"               => true,
      "web/third_party/hooks.js"       => true,
    })
  end
end
