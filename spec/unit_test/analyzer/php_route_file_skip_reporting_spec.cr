require "file_utils"
require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/drupal"
require "../../../src/analyzer/analyzers/php/symfony"
require "../../../src/analyzer/analyzers/php/codeigniter"
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
end
