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
end
