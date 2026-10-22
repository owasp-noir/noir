require "../../spec_helper"
require "../../../src/analyzer/analyzer.cr"

describe "filter_redundant_generic_techs" do
  # php_pure used to be dropped here whenever a PHP framework was detected,
  # because it emitted every `.php` file as an endpoint. It now resolves URLs
  # against the document root, so the noise is gone at the source and the rule
  # was removed — keeping it would still lose a legacy script living inside
  # `public/` next to a framework app (#2358).
  it "keeps php_pure when a framework-specific php analyzer is present" do
    filter_redundant_generic_techs(["php_pure", "php_laravel"]).should eq(["php_pure", "php_laravel"])
    filter_redundant_generic_techs(["php_symfony", "php_pure"]).should eq(["php_symfony", "php_pure"])
  end

  it "keeps php_pure when no framework-specific php analyzer is present" do
    filter_redundant_generic_techs(["php_pure"]).should eq(["php_pure"])
  end

  it "does not affect unrelated technologies" do
    techs = ["php_laravel", "python_django", "js_express"]
    filter_redundant_generic_techs(techs).should eq(techs)
  end

  # Regression guard: a repo-wide framework hit must never suppress a
  # generic stdlib analyzer. In a monorepo the two can belong to different
  # applications (a standalone net/http admin listener beside a Gin API,
  # a standalone Starlette service beside a FastAPI one), so dropping the
  # generic analyzer silently loses real endpoints.
  it "keeps go_http when a Go framework analyzer is also present" do
    filter_redundant_generic_techs(["go_http", "go_gin"]).should eq(["go_http", "go_gin"])
  end

  it "keeps js_http when a JS framework analyzer is also present" do
    filter_redundant_generic_techs(["js_http", "js_express"]).should eq(["js_http", "js_express"])
  end

  it "keeps python_starlette when python_fastapi is also present" do
    filter_redundant_generic_techs(["python_fastapi", "python_starlette"]).should eq(["python_fastapi", "python_starlette"])
  end

  # The four supersede rules, which had no unit coverage at all until now —
  # `spec/functional_test/testers/php/lumen_spec.cr` tested one of them.
  # Each is asserted in both input orders, because the rules used to be an
  # `if` chain reading a mutating array and the new form evaluates presence
  # against the input list.
  {
    {"php_lumen", "php_laravel"},
    {"elixir_bandit", "elixir_plug"},
    {"zig_jetzig", "zig_httpz"},
    {"zig_tokamak", "zig_httpz"},
    {"php_drupal", "php_symfony"},
    {"php_magento", "php_symfony"},
  }.each do |superseder, superseded|
    it "drops #{superseded} when #{superseder} is present" do
      filter_redundant_generic_techs([superseder, superseded]).should eq([superseder])
      filter_redundant_generic_techs([superseded, superseder]).should eq([superseder])
    end

    it "keeps #{superseded} when #{superseder} is absent" do
      filter_redundant_generic_techs([superseded]).should eq([superseded])
    end
  end

  it "preserves input order for the techs it keeps" do
    techs = ["python_django", "php_laravel", "js_express", "php_lumen", "go_gin"]
    filter_redundant_generic_techs(techs).should eq(["python_django", "js_express", "php_lumen", "go_gin"])
  end
end
