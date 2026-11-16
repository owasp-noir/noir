require "../../spec_helper"
require "../../../src/ai_context/augmentor"
require "../../../src/cli/inspect"

private def with_temp_transitive_tree(files : Hash(String, String), & : String ->)
  root = "#{Dir.tempdir}/noir-transitive-#{Random.rand(1_000_000)}"
  Dir.mkdir_p(root)
  CodeLocator.instance.clear_all
  begin
    files.each do |rel, content|
      full = File.join(root, rel)
      Dir.mkdir_p(File.dirname(full))
      File.write(full, content)
      CodeLocator.instance.register_file(full, content)
    end
    yield root
  ensure
    CodeLocator.instance.clear_all
    FileUtils.rm_rf(root) if Dir.exists?(root)
  end
end

describe "NoirAIContext transitive callee sink resolution" do
  it "enforces the 3-hop depth ceiling below the handler" do
    py = <<-PY
      import subprocess

      def hop3(x):
          return subprocess.run(x, shell=True)

      def hop2(x):
          return hop3(x)

      def hop1(x):
          return hop2(x)

      def hop0(x):
          return hop1(x)
      PY

    with_temp_transitive_tree({"app.py" => py}) do |root|
      app_path = File.join(root, "app.py")

      within_cap = Endpoint.new("/within", "POST")
      within_cap.push_callee(Callee.new("hop1", app_path, 9))

      beyond_cap = Endpoint.new("/beyond", "POST")
      beyond_cap.push_callee(Callee.new("hop0", app_path, 12))

      results = NoirAIContext.apply([within_cap, beyond_cap])

      within_sinks = results[0].ai_context.not_nil!.sinks
      within_sinks.map(&.kind).should eq(["command_exec"])
      within_sinks[0].line.should eq(4)
      within_sinks[0].description.to_s.should contain("hop1 -> hop2 -> hop3")

      (results[1].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end

  it "terminates on mutually recursive project functions and skips ambiguous definitions" do
    py = <<-PY
      import subprocess

      def ping(n):
          return pong(n - 1)

      def pong(n):
          return ping(n - 1)

      def dup(x):
          return subprocess.run(x, shell=True)

      def dup(x):
          return x
      PY

    with_temp_transitive_tree({"cycle.py" => py}) do |root|
      path = File.join(root, "cycle.py")
      cycle_ep = Endpoint.new("/cycle", "GET")
      cycle_ep.push_callee(Callee.new("ping", path, 3))

      dup_ep = Endpoint.new("/dup", "POST")
      dup_ep.details = Details.new(PathInfo.new(path, 15))
      dup_ep.push_callee(Callee.new("dup", path, 16))

      results = NoirAIContext.apply([cycle_ep, dup_ep])
      (results[0].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
      (results[1].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end

  it "does not displace existing direct sinks when the sink bucket is already full" do
    py = <<-PY
      import subprocess

      def run_cmd(x):
          return subprocess.run(x, shell=True)
      PY

    with_temp_transitive_tree({"full.py" => py}) do |root|
      path = File.join(root, "full.py")
      endpoint = Endpoint.new("/full", "POST")
      AIContext::MAX_PER_SECTION.times do |i|
        endpoint.push_callee(Callee.new("db#{i}.query", path, i + 10))
      end
      endpoint.push_callee(Callee.new("run_cmd", path, 3))

      results = NoirAIContext.apply([endpoint])
      sinks = results[0].ai_context.not_nil!.sinks
      sinks.size.should eq(AIContext::MAX_PER_SECTION)
      sinks.all?(&.kind.==("sql")).should be_true
    end
  end

  it "does not treat Go io/fs fs.ErrNotExist or fs.Sub, or html.replace, as transitive sinks" do
    go_code = <<-GO
      package fileserver

      import (
          "errors"
          "io/fs"
      )

      func CheckErr(err error) bool {
          return errors.Is(err, fs.ErrNotExist)
      }

      func SubTree(embedded fs.FS, p string) (fs.FS, error) {
          return fs.Sub(embedded, p)
      }
      GO

    py_code = <<-PY
      def format_doc(html):
          return html.replace("A", "B")
      PY

    with_temp_transitive_tree({"fileserver.go" => go_code, "docs.py" => py_code}) do |root|
      go_path = File.join(root, "fileserver.go")
      py_path = File.join(root, "docs.py")

      go_ep1 = Endpoint.new("/err", "GET")
      go_ep1.push_callee(Callee.new("CheckErr", go_path, 8))

      go_ep2 = Endpoint.new("/sub", "GET")
      go_ep2.push_callee(Callee.new("SubTree", go_path, 12))

      py_ep = Endpoint.new("/docs", "GET")
      py_ep.push_callee(Callee.new("format_doc", py_path, 1))

      results = NoirAIContext.apply([go_ep1, go_ep2, py_ep])
      (results[0].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
      (results[1].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
      (results[2].ai_context.try(&.sinks) || [] of AIContextEntry).should be_empty
    end
  end

  it "resolves Go module imports when CodeLocator paths use backslash separators" do
    go_mod = "module example.com/winapp\n\ngo 1.22\n"
    handler_go = <<-GO
      package handler

      import "example.com/winapp/service"

      func Export(cmd string) {
          service.Run(cmd)
      }
      GO
    service_go = <<-GO
      package service

      import "os/exec"

      func Run(cmd string) {
          exec.Command("sh", "-c", cmd).Run()
      }
      GO

    CodeLocator.instance.clear_all
    begin
      CodeLocator.instance.register_file("winapp/go.mod", go_mod)
      CodeLocator.instance.register_file("winapp\\handler\\user.go", handler_go)
      CodeLocator.instance.register_file("winapp\\service\\user.go", service_go)

      ep = Endpoint.new("/export", "POST")
      ep.push_callee(Callee.new("service.Run", "winapp\\handler\\user.go", 6))

      results = NoirAIContext.apply([ep])
      sinks = results[0].ai_context.not_nil!.sinks
      sinks.map(&.kind).should eq(["command_exec"])
      sinks[0].path.should eq("winapp\\service\\user.go")
      sinks[0].line.should eq(6)
    ensure
      CodeLocator.instance.clear_all
    end
  end
end
