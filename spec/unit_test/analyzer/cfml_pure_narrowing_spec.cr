require "../../spec_helper"
require "../../../src/analyzer/analyzer.cr"

# `cfml_pure` is the one tech noir *narrows* rather than drops when a more
# specific analyzer is present. The distinction is the point: dropping it
# outright is what the framework-shadows-framework rules in
# `NoirTechs::SUPERSEDES` do, and doing that to `cfml_pure` cost real
# findings — the `access="remote"` methods on a ColdBox app's proxy
# components are HTTP-callable whatever framework fronts them, and no
# framework analyzer emits them.
#
# The decision had no coverage at all: it lived inline in
# `analysis_endpoints`, which runs every analyzer, so there was nothing to
# call. `cfml_components_only?` exists so there is.
describe "cfml_components_only?" do
  CFML_FRAMEWORK_TECHS.each do |framework|
    it "narrows cfml_pure when #{framework} owns the route table" do
      cfml_components_only?(["cfml_pure", framework]).should be_true
      cfml_components_only?([framework, "cfml_pure"]).should be_true
    end
  end

  it "leaves cfml_pure at full scope when it is the only CFML tech" do
    cfml_components_only?(["cfml_pure"]).should be_false
  end

  # The page surface is only owned when a *CFML* framework is present. A
  # PHP or Java framework in the same monorepo says nothing about who serves
  # the `.cfm` files.
  it "ignores non-CFML frameworks" do
    cfml_components_only?(["cfml_pure", "php_laravel", "java_spring"]).should be_false
  end

  it "stays false when cfml_pure is not selected" do
    cfml_components_only?(["cfml_coldbox"]).should be_false
    cfml_components_only?([] of String).should be_false
  end

  # Guards the narrowing against being quietly converted back into a drop.
  # `cfml_pure` must survive tech selection whenever a CFML framework is
  # present — otherwise the generic analyzer never runs and the
  # remote-method surface disappears again, which is the regression #2358
  # is named after on the PHP side.
  it "keeps cfml_pure in the selected techs so there is something to narrow" do
    CFML_FRAMEWORK_TECHS.each do |framework|
      filter_redundant_generic_techs(["cfml_pure", framework]).should contain("cfml_pure")
    end
  end
end
