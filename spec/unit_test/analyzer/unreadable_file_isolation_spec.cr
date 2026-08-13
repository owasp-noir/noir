require "file_utils"
require "../../spec_helper"
require "../../../src/utils/string_extension"
require "../../../src/analyzer/analyzers/go/gin"
require "../../../src/models/code_locator"
require "../../../src/models/logger"

# One unreadable source file must cost that file and nothing else.
#
# `File::AccessDeniedError` is a **sibling** of `File::NotFoundError` under
# `File::Error`, not a subclass, so the `rescue File::NotFoundError` that 42
# read sites carried did not catch an unreadable file. In `GoEngine`'s
# synchronous pre-phase readers the escaping exception was not caught until
# the per-analyzer handler in `analysis_endpoints`, which abandons the whole
# analyzer: measured on a flat 501-file Gin tree, one `chmod 000` file took
# the analyzer from 501 endpoints to **zero**, reported as a single warning
# line.
#
# This drives the analyzer directly rather than through `detect_techs`,
# because the detector registers `.go` paths only after reading them — so
# once the detector's own read fails, the analyzer never sees the file. The
# reachable-in-production shape is `-t <tech> --only-techs <other>`, where a
# tech is selected without its detector running: the path is registered
# content-free and the analyzer is the first thing to open it.
describe "analyzer file-read isolation" do
  it "keeps the other files when one is unreadable" do
    temp_dir = File.tempname("noir_unreadable_analyzer")
    Dir.mkdir_p(temp_dir)
    unreadable = File.join(temp_dir, "locked.go")

    begin
      File.write(File.join(temp_dir, "go.mod"), "module repro\n\ngo 1.21\n")
      readable = (0...5).map do |i|
        path = File.join(temp_dir, "route_#{i}.go")
        File.write(path, <<-GO)
          package main

          import "github.com/gin-gonic/gin"

          func Register#{i}(r *gin.Engine) {
            r.GET("/ok#{i}", func(c *gin.Context) {})
          }
          GO
        path
      end

      File.write(unreadable, <<-GO)
        package main

        import "github.com/gin-gonic/gin"

        func RegisterLocked(r *gin.Engine) {
          r.GET("/locked", func(c *gin.Context) {})
        }
        GO
      File.chmod(unreadable, 0o000)

      # Mode bits do not apply to root, and a spec that cannot establish the
      # condition it tests must say so rather than pass. Probe by reading:
      # `File::Info#readable?` reports the mode bits, which for root says
      # "no" about a file root can in fact read.
      still_readable = begin
        File.read(unreadable)
        true
      rescue File::Error
        false
      end
      pending! "requires a non-root user: mode 000 is not enforced here" if still_readable

      locator = CodeLocator.instance
      locator.clear_all
      # Register every path without content, which is what the detector does
      # for a file no detector is applicable to.
      (readable + [unreadable]).each { |path| locator.register_path(path) }

      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = Analyzer::Go::Gin.new(options).analyze

      urls = endpoints.map(&.url).sort!
      urls.should eq((0...5).map { |i| "/ok#{i}" })
      urls.should_not contain("/locked")
    ensure
      File.chmod(unreadable, 0o644) if File.exists?(unreadable)
      FileUtils.rm_rf(temp_dir) if temp_dir
      CodeLocator.instance.clear_all
    end
  end
end
