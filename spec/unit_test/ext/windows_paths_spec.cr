require "spec"
require "file_utils"
require "../../../src/ext/windows_paths"

describe Noir::WindowsPaths do
  describe ".to_slash" do
    it "turns backslashes into slashes" do
      Noir::WindowsPaths.to_slash("C:\\a\\b.cr").should eq("C:/a/b.cr")
      Noir::WindowsPaths.to_slash("\\\\server\\share\\x").should eq("//server/share/x")
    end

    it "leaves an extended-length path verbatim" do
      Noir::WindowsPaths.to_slash("\\\\?\\C:\\a\\b").should eq("\\\\?\\C:\\a\\b")
    end
  end

  # The stdlib overrides themselves only exist in a Windows build.
  {% if flag?(:windows) %}
    describe "stdlib overrides" do
      it "returns /-separated paths from every wrapped method" do
        File.join("C:\\a", "b", "c.cr").should eq("C:/a/b/c.cr")
        File.join(["C:\\a", "b"]).should eq("C:/a/b")
        File.expand_path("x\\y").should_not contain('\\')
        Dir.current.should_not contain('\\')
        Dir.tempdir.should_not contain('\\')
        File.realpath(Dir.tempdir).should_not contain('\\')
      end

      it "answers false for an empty path instead of raising" do
        File.exists?("").should be_false
      end

      it "round-trips through the filesystem" do
        dir = File.join(Dir.tempdir, "noir-windows-paths-#{Random.rand(1_000_000)}")
        Dir.mkdir_p(File.join(dir, "sub"))
        begin
          file = File.join(dir, "sub", "a.txt")
          File.write(file, "ok")
          File.read(file).should eq("ok")
          Dir.glob("#{dir}/**/*.txt").should eq([file])
          File.realpath(file).should eq(File.expand_path(file))
        ensure
          FileUtils.rm_rf(dir)
        end
      end
    end
  {% end %}
end
