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

  it "drops js_http when a JS framework analyzer is present" do
    filter_redundant_generic_techs(["js_http", "js_express"]).should eq(["js_express"])
    filter_redundant_generic_techs(["js_hono", "js_http", "js_fastify"]).should eq(["js_hono", "js_fastify"])
  end

  it "keeps js_http when no JS framework analyzer is present" do
    filter_redundant_generic_techs(["js_http"]).should eq(["js_http"])
  end

  it "drops python_starlette when python_fastapi is present" do
    filter_redundant_generic_techs(["python_fastapi", "python_starlette"]).should eq(["python_fastapi"])
  end

  it "keeps python_starlette alone" do
    filter_redundant_generic_techs(["python_starlette"]).should eq(["python_starlette"])
  end

  it "drops go_http when a Go framework analyzer is present" do
    filter_redundant_generic_techs(["go_http", "go_gin"]).should eq(["go_gin"])
  end
end
