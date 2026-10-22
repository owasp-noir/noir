require "../../spec_helper"
require "../../../src/models/noir"
require "file_utils"

# Seconds to scan a tree written by `files`, plus the endpoint count.
private def timed_scan(files : Hash(String, String)) : Tuple(Float64, Int32)
  root = File.tempname("noir-python-scaling")
  files.each do |path, content|
    FileUtils.mkdir_p(File.dirname(File.join(root, path)))
    File.write(File.join(root, path), content)
  end
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(root)])
  runner = NoirRunner.new(options)
  started = Time.instant
  runner.detect
  runner.analyze
  {(Time.instant - started).total_seconds, runner.endpoints.size}
ensure
  CodeLocator.instance.reset_files
  FileUtils.rm_rf(root) if root && Dir.exists?(root)
end

# One module holding every handler, routed one by one: resolving each route
# used to re-read the module from the top, so 8x the handlers cost ~64x.
# Linear scans measure ~4-6x per 8x/16x here; the bound is 4x the size factor.
private def assert_linear(small_n = 250, large_n = 2000, &tree : Int32 -> Hash(String, String))
  small, small_count = timed_scan(tree.call(small_n))
  large, large_count = timed_scan(tree.call(large_n))
  small_count.should be >= small_n
  large_count.should be >= large_n
  factor = large_n / small_n
  (large / {small, 0.005}.max).should be < factor * 4
end

describe "Python per-route handler lookup scaling" do
  it "stays linear for Django views in one module" do
    assert_linear do |n|
      {
        "manage.py"        => "import os\nos.environ.setdefault(\"DJANGO_SETTINGS_MODULE\", \"proj.settings\")\n",
        "proj/__init__.py" => "",
        "proj/settings.py" => "ROOT_URLCONF = \"proj.urls\"\n",
        "proj/urls.py"     => "from django.urls import path\nfrom app import views\nurlpatterns = [\n" +
          (0...n).join { |i| "    path(\"r#{i}/\", views.v#{i}),\n" } + "]\n",
        "app/__init__.py" => "",
        "app/views.py"    => (0...n).join { |i| "def v#{i}(request):\n    \"\"\"설명 #{i}\"\"\"\n    return request.GET.get(\"q#{i}\")\n\n" },
      }
    end
  end

  it "stays linear for Tornado handlers in one module" do
    assert_linear do |n|
      {
        "requirements.txt" => "tornado\n",
        "app.py"           => "import tornado.web\n" +
          (0...n).join { |i| "class H#{i}(tornado.web.RequestHandler):\n    def get(self):\n        self.write(self.get_argument(\"q#{i}\"))\n\n" } +
          "app = tornado.web.Application([\n" + (0...n).join { |i| "    (r\"/r#{i}\", H#{i}),\n" } + "])\n",
      }
    end
  end

  it "stays linear for Litestar handlers in one module" do
    assert_linear(250, 4000) do |n|
      {
        "requirements.txt" => "litestar\n",
        "app.py"           => "from litestar import get\n" +
          (0...n).join { |i| "@get(\"/r#{i}\")\nasync def h#{i}(q#{i}: str = \"가\") -> str:\n    \"\"\"설명 — 한국어 ✓ #{i}\"\"\"\n    return \"x\"\n\n" },
      }
    end
  end
end
