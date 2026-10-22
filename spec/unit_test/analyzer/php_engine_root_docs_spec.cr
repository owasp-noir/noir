require "../../spec_helper"
require "../../../src/analyzer/analyzers/php/php"
require "../../../src/analyzer/analyzers/php/laravel"

class PhpRootDocsPureHarness < Analyzer::Php::Php
  def accepts?(path : String) : Bool
    scan_accepts?(path)
  end
end

class PhpRootDocsLaravelHarness < Analyzer::Php::Laravel
  def accepts?(path : String) : Bool
    scan_accepts?(path)
  end
end

private def options_for(base : String) : Hash(String, YAML::Any)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  options
end

# A root `docs/` tree holds runnable doc snippets in a framework repo (API
# Platform `docs/guides`), but a section of a plain PHP site is served.
describe "PhpEngine root docs/ tree" do
  base = "/srv/app"

  it "is a served section for the plain PHP analyzer" do
    pure = PhpRootDocsPureHarness.new(options_for(base))

    pure.accepts?("#{base}/docs/index.php").should be_true
    pure.accepts?("#{base}/docs/search.php").should be_true
    pure.accepts?("#{base}/lib/docs/page.php").should be_true
  end

  it "is skipped for a framework adapter" do
    laravel = PhpRootDocsLaravelHarness.new(options_for(base))

    laravel.accepts?("#{base}/docs/guides/declare-a-resource.php").should be_false
    laravel.accepts?("#{base}/lib/docs/page.php").should be_true
  end

  it "keeps skipping tests for the plain PHP analyzer" do
    pure = PhpRootDocsPureHarness.new(options_for(base))

    pure.accepts?("#{base}/tests/Feature/FooTest.php").should be_false
    pure.accepts?("#{base}/docs/tests/Foo.php").should be_false
  end
end
