require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/drupal"
require "../../../src/analyzer/analyzers/php/symfony"
require "../../../src/analyzer/analyzers/php/codeigniter"
require "../../../src/analyzer/analyzers/php/slim"
require "../../../src/analyzer/analyzers/php/cakephp"
require "../../../src/analyzer/analyzers/php/thinkphp"
require "../../../src/analyzer/analyzers/php/lumen"
require "../../../src/models/skipped_files"

# The PHP route-file analyzers rescue their own parse errors (so whatever a
# file yielded before the failure is kept), which also kept the failure away
# from `Analyzer#scan_files`: a malformed routing file produced `errors: []`
# and `--strict` exited 0.
describe "PHP route-file parse failure reporting" do
  before_each { Noir::SkippedFiles.clear }
  after_each { Noir::SkippedFiles.clear }

  {
    {"drupal", "mod/mod.routing.yml", "mod.a:\n  path: '/a'\n  methods: [GET\n"},
    {"symfony", "config/routes.yaml", "a:\n  path: /a\n  methods: [GET\n"},
  }.each do |name, relative, content|
    it "records an unparsable #{name} routing file" do
      dir = File.tempname("noir_php_route_skip")
      path = File.join(dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, content)

      begin
        analyzer = name == "drupal" ? Analyzer::Php::Drupal.new(create_test_options) : Analyzer::Php::Symfony.new(create_test_options)
        analyzer.analyze_file(path).should be_empty

        Noir::SkippedFiles.count.should eq(1)
        failure = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first
        failure.tech.should eq("php_#{name}")
        failure.message.should contain(path)
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end

  # Each nested `$routes->group(...)` callback was one more recursion with no
  # bound; ~2300 levels overflowed the stack and killed the whole scan.
  it "skips only the CodeIgniter group nesting past the depth limit" do
    dir = File.tempname("noir_php_route_skip")
    path = File.join(dir, "app/Config/Routes.php")
    Dir.mkdir_p(File.dirname(path))
    depth = 3000
    File.write(path, "<?php\n$routes->get('top', 'Home::index');\n" +
                     "$routes->group('a', function ($routes) {\n" * depth +
                     "$routes->get('x', 'Home::index');\n" + "});\n" * depth)

    begin
      # The routes outside the runaway nesting are kept.
      Analyzer::Php::CodeIgniter.new(create_test_options).analyze_file(path).map(&.url).should eq(["/top"])
      Noir::SkippedFiles.count.should eq(1)
      Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first.message.should contain("nested deeper")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  # Same unbounded group recursion in these adapters; 3000 levels used to
  # end the process with "Stack overflow".
  {
    {"slim", "public/index.php", "<?php\nuse Slim\\Factory\\AppFactory;\n$app->get('/top', function ($req, $res) { return $res; });\n",
     "$app->group('/a', function ($app) {\n", "$app->get('/x', function ($req, $res) { return $res; });\n", "});\n", ""},
    {"cakephp", "config/routes.php", "<?php\nreturn function ($routes): void {\n$routes->get('/top', 'Pages::index');\n",
     "$routes->scope('/a', function ($routes): void {\n", "$routes->get('/x', 'Pages::index');\n", "});\n", "};\n"},
    {"thinkphp", "route/app.php", "<?php\nuse think\\facade\\Route;\nRoute::get('top', 'index/top');\n",
     "Route::group('a', function () {\n", "Route::get('x', 'index/x');\n", "});\n", ""},
    {"lumen", "routes/web.php", "<?php\n$router->get('/top', function () {});\n",
     "$router->group(['prefix' => 'a'], function () use ($router) {\n", "$router->get('x', function () {});\n", "});\n", ""},
  }.each do |name, relative, head, open, inner, close, tail|
    it "skips only the #{name} group nesting past the depth limit" do
      dir = File.tempname("noir_php_route_skip")
      path = File.join(dir, relative)
      Dir.mkdir_p(File.dirname(path))
      depth = 3000
      File.write(path, head + open * depth + inner + close * depth + tail)

      begin
        options = create_test_options
        options["base"] = YAML::Any.new([YAML::Any.new(dir)])
        analyzer = case name
                   when "slim"     then Analyzer::Php::Slim.new(options)
                   when "cakephp"  then Analyzer::Php::CakePHP.new(options)
                   when "thinkphp" then Analyzer::Php::ThinkPHP.new(options)
                   else                 Analyzer::Php::Lumen.new(options)
                   end
        analyzer.analyze_file(path).map(&.url).should eq(["/top"])
        Noir::SkippedFiles.count.should eq(1)
        Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).first.message.should contain("nested deeper")
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
