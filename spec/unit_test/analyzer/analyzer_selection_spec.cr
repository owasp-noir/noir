require "../../spec_helper"
require "../../../src/analyzer/analyzer.cr"

describe "filter_redundant_generic_techs" do
  it "drops php_pure when a framework-specific php analyzer is present" do
    filter_redundant_generic_techs(["php_pure", "php_laravel"]).should eq(["php_laravel"])
    filter_redundant_generic_techs(["php_symfony", "php_pure"]).should eq(["php_symfony"])
  end

  it "keeps php_pure when no framework-specific php analyzer is present" do
    filter_redundant_generic_techs(["php_pure"]).should eq(["php_pure"])
  end

  it "does not affect unrelated technologies" do
    techs = ["php_laravel", "python_django", "js_express"]
    filter_redundant_generic_techs(techs).should eq(techs)
  end
end
