require "file_utils"
require "../../spec_helper"
require "../../../src/models/code_locator"
require "../../../src/analyzer/analyzers/python/django"

# A root urlconf including thousands of lists imported from one module used
# to re-parse that whole module once per list (quadratic); it is parsed once.
describe "Django imported url lists scaling" do
  it "reads many lists imported from one module in linear time" do
    count = 2000
    temp_dir = File.tempname("django_imported_lists_scaling")
    files = {
      "manage.py"        => %(import os\nos.environ.setdefault("DJANGO_SETTINGS_MODULE", "proj.settings")\n),
      "proj/__init__.py" => "",
      "proj/settings.py" => %(ROOT_URLCONF = "proj.urls"\n),
      "app/__init__.py"  => "",
      "app/views.py"     => %(from django.http import HttpResponse\ndef a(request):\n    return HttpResponse("a")\n),
      "app/lists.py"     => String.build do |io|
        io << "from django.urls import path\nfrom app import views\n"
        count.times { |i| io << %(l#{i} = [path("r#{i}/", views.a)]\n) }
      end,
      "proj/urls.py" => String.build do |io|
        io << "from django.urls import path, include\nfrom app.lists import ("
        io << (0...count).map { |i| "l#{i}" }.join(", ") << ")\nurlpatterns = [\n"
        count.times { |i| io << %(    path("m#{i}/", include(l#{i})),\n) }
        io << "]\n"
      end,
    }
    CodeLocator.instance.clear_all
    files.each do |relative, content|
      path = File.join(temp_dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)
      CodeLocator.instance.register_file(path, content)
    end

    begin
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(temp_dir)])
      endpoints = [] of Endpoint
      elapsed = Time.measure { endpoints = Analyzer::Python::Django.new(options).analyze }

      endpoints.map(&.url).to_set.should eq((0...count).map { |i| "/m#{i}/r#{i}/" }.to_set)
      elapsed.should be < 10.seconds
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(temp_dir)
    end
  end
end
