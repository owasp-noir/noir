require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/java/armeria"
require "../../../src/analyzer/analyzers/java/jsp"
require "../../../src/analyzer/analyzers/java/vertx"
require "../../../src/analyzer/analyzers/python/python_helper"
require "../../../src/analyzer/analyzers/python/django"
require "../../../src/models/code_locator"
require "../../../src/models/skipped_files"

# A worker fiber that raises anything other than an `IO::Error` must not take
# the scan down with it.
#
# `java/armeria.cr`, `java/jsp.cr`, `java/vertx.cr` and `python/django.cr`
# each carried a hand-inlined copy of `Analyzer#parallel_analyze` that
# predated the two fixes the base class already had:
#
#   1. the worker rescue was `rescue e : IO::Error`, so a tree-sitter parse
#      timeout or an `IndexError` on a malformed file killed the fiber, and
#   2. the producer ran `channel.close` as a trailing statement rather than
#      inside an `ensure`.
#
# Once every worker was dead the producer parked forever on `send` into a
# full 128-slot channel and `WaitGroup.wait` never returned: an idle deadlock
# with no output, no exit code and nothing to kill it but SIGKILL. Verified
# against the pre-fix build with a 301-file Armeria project and
# `NOIR_PARSE_TIMEOUT_MS=1 --concurrency 1` — 90 s at 0% CPU and 0 bytes of
# stdout, where the same scan finishes in ~5 s once the analyzer rides the
# shared pool.
#
# Each case below registers one poisoned path ahead of enough good files to
# fill the channel buffer, forces a non-IO exception out of that file's read,
# and asserts the three things the base class guarantees: the scan
# terminates, the remaining files are still analyzed, and the failure is
# recorded so it reaches the `errors` array and `--strict`.
#
# The probes deliberately live outside the `Analyzer::` namespace — the
# analyzer registry in `src/analyzer/analyzer.cr` derives itself from
# `Analyzer.all_subclasses` filtered on that prefix, so a throwaway subclass
# named anything else does not join it.
module WorkerPoolProbe
  POISON_MARKER = "PoisonWorker"

  # More than `Analyzer::DEFAULT_CHANNEL_CAPACITY` (128), so the producer is
  # still mid-`send` when the poisoned file reaches the (single) worker. With
  # a smaller file set the producer would drain into the buffer and close,
  # and the bug would show up only as lost endpoints rather than as a hang.
  GOOD_FILE_COUNT = 200

  # `File.exists?`/`File.read` on these paths would succeed; the override is
  # what makes the read raise, and `ArgumentError` is deliberately not an
  # `IO::Error` — that is the whole point of the regression.
  module RaiseOnPoison
    def read_file_content(path : String) : String
      if path.includes?(WorkerPoolProbe::POISON_MARKER)
        raise ArgumentError.new("synthetic non-IO worker failure")
      end
      super
    end
  end

  class Armeria < Analyzer::Java::Armeria
    include RaiseOnPoison
  end

  class Jsp < Analyzer::Java::Jsp
    include RaiseOnPoison
  end

  class Vertx < Analyzer::Java::Vertx
    include RaiseOnPoison
  end

  class Django < Analyzer::Python::Django
    include RaiseOnPoison
  end
end

# Runs `block` in its own fiber and reports whether it finished. A plain call
# would hang the whole suite on a regression; the `timeout` branch also keeps
# the event loop alive, so the runtime does not abort with "deadlock
# detected" before the assertion can fail.
private def completes_within?(span : Time::Span, &block : -> Nil) : Bool
  done = Channel(Exception?).new(1)
  spawn do
    block.call
    done.send(nil)
  rescue e
    done.send(e)
  end

  select
  when error = done.receive
    raise error if error
    true
  when timeout(span)
    false
  end
end

private def probe_options(base : String) : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  # One worker: the deadlock needs every worker dead, and one poisoned file
  # is enough to kill one worker.
  options["concurrency"] = YAML::Any.new("1")
  options
end

private def register_probe_paths(paths : Array(String))
  locator = CodeLocator.instance
  locator.clear_all
  paths.each { |path| locator.register_path(path) }
end

describe "analyzer worker-pool resilience" do
  after_each do
    CodeLocator.instance.clear_all
    Noir::SkippedFiles.clear
  end

  it "keeps Armeria running when a worker raises a non-IO exception" do
    dir = File.tempname("noir_pool_armeria")
    Dir.mkdir_p(dir)

    begin
      # A `.kt` poison: Armeria's two synchronous pre-phases walk `.java`
      # only, so this isolates the failure to the worker pool.
      poison = File.join(dir, "#{WorkerPoolProbe::POISON_MARKER}.kt")
      File.write(poison, "package com.example\n")

      good = (0...WorkerPoolProbe::GOOD_FILE_COUNT).map do |i|
        path = File.join(dir, "Svc#{i}.java")
        File.write(path, <<-JAVA)
          package com.example;

          import com.linecorp.armeria.server.annotation.Get;

          public class Svc#{i} {
              @Get("/svc#{i}")
              public String list() {
                  return "ok";
              }
          }
          JAVA
        path
      end

      register_probe_paths([poison] + good)
      Noir::SkippedFiles.clear

      analyzer = WorkerPoolProbe::Armeria.new(probe_options(dir))
      endpoints = [] of Endpoint
      finished = completes_within?(30.seconds) { endpoints = analyzer.analyze }

      finished.should be_true
      endpoints.map(&.url).sort!.should eq((0...WorkerPoolProbe::GOOD_FILE_COUNT).map { |i| "/svc#{i}" }.sort!)
      Noir::SkippedFiles.failures.map(&.tech).should contain("java_armeria")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps JSP running when a worker raises a non-IO exception" do
    dir = File.tempname("noir_pool_jsp")
    Dir.mkdir_p(dir)

    begin
      # A `.jsp` poison: `collect_servlet_methods` pre-reads `.java` files
      # only, so this failure can only come from the worker pool.
      poison = File.join(dir, "#{WorkerPoolProbe::POISON_MARKER}.jsp")
      File.write(poison, "<html></html>\n")

      good = (0...WorkerPoolProbe::GOOD_FILE_COUNT).map do |i|
        path = File.join(dir, "page#{i}.jsp")
        File.write(path, %(<%= request.getParameter("q#{i}") %>\n))
        path
      end

      register_probe_paths([poison] + good)
      Noir::SkippedFiles.clear

      analyzer = WorkerPoolProbe::Jsp.new(probe_options(dir))
      endpoints = [] of Endpoint
      finished = completes_within?(30.seconds) { endpoints = analyzer.analyze }

      finished.should be_true
      endpoints.map(&.url).sort!.should eq((0...WorkerPoolProbe::GOOD_FILE_COUNT).map { |i| "/page#{i}.jsp" }.sort!)
      Noir::SkippedFiles.failures.map(&.tech).should contain("java_jsp")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps Vert.x running when a worker raises a non-IO exception" do
    dir = File.tempname("noir_pool_vertx")
    Dir.mkdir_p(dir)

    begin
      poison = File.join(dir, "#{WorkerPoolProbe::POISON_MARKER}.java")
      File.write(poison, "package com.example;\n")

      good = (0...WorkerPoolProbe::GOOD_FILE_COUNT).map do |i|
        path = File.join(dir, "Verticle#{i}.java")
        File.write(path, <<-JAVA)
          package com.example;

          import io.vertx.ext.web.Router;

          public class Verticle#{i} {
              public void start() {
                  Router router = Router.router(vertx);
                  router.get("/v#{i}").handler(ctx -> ctx.end());
              }
          }
          JAVA
        path
      end

      register_probe_paths([poison] + good)
      Noir::SkippedFiles.clear

      analyzer = WorkerPoolProbe::Vertx.new(probe_options(dir))
      endpoints = [] of Endpoint
      finished = completes_within?(30.seconds) { endpoints = analyzer.analyze }

      finished.should be_true
      endpoints.map(&.url).sort!.should eq((0...WorkerPoolProbe::GOOD_FILE_COUNT).map { |i| "/v#{i}" }.sort!)
      Noir::SkippedFiles.failures.map(&.tech).should contain("java_vertx")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "keeps Django running when a worker raises a non-IO exception" do
    dir = File.tempname("noir_pool_django")
    Dir.mkdir_p(File.join(dir, "proj"))
    Dir.mkdir_p(File.join(dir, "filler"))

    begin
      # `find_root_django_urls` only reads a file whose name looks like a
      # settings module, so the poison has to look like one too.
      poison = File.join(dir, "#{WorkerPoolProbe::POISON_MARKER}_settings.py")
      File.write(poison, "ROOT_URLCONF = \"proj.urls\"\n")

      filler = (0...WorkerPoolProbe::GOOD_FILE_COUNT).map do |i|
        path = File.join(dir, "filler", "mod#{i}.py")
        File.write(path, "VALUE = #{i}\n")
        path
      end

      settings = File.join(dir, "proj", "settings.py")
      File.write(settings, "ROOT_URLCONF = \"proj.urls\"\n")

      urls = File.join(dir, "proj", "urls.py")
      File.write(urls, <<-PY)
        from django.urls import path
        from . import views

        urlpatterns = [
            path("api/ping", views.ping),
            path("api/pong", views.pong),
        ]
        PY

      # The real settings module is registered last: if the poisoned read
      # kills the worker, the producer never gets far enough to hand it over
      # and the analyzer reports nothing at all.
      register_probe_paths([poison] + filler + [urls, settings])
      Noir::SkippedFiles.clear

      analyzer = WorkerPoolProbe::Django.new(probe_options(dir))
      endpoints = [] of Endpoint
      finished = completes_within?(30.seconds) { endpoints = analyzer.analyze }

      finished.should be_true
      endpoints.map(&.url).sort!.should eq(["/api/ping", "/api/pong"])
      Noir::SkippedFiles.failures.map(&.tech).should contain("python_django")
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
