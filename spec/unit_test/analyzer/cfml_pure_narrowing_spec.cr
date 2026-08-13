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

# The narrowing is communicated to `Analyzer::Cfml::Pure` by writing a key
# into the options hash `analysis_endpoints` was handed — the caller's hash,
# which nothing clears between passes. `CodeLocator`'s lifecycle resets do not
# reach it, because it is not a locator key.
#
# So the write has to be unconditional. While it was `if narrowing?` /
# assign-true, a `true` from one pass survived into the next call on the same
# hash: an embedder scanning a ColdBox app and then a plain-CFML app got the
# second scan narrowed to components-only and silently lost its entire `.cfm`
# page surface. Same shape as the scan-lifecycle leak #2503 fixed, in the one
# remaining channel that carries state between passes.
describe "apply_cfml_components_only!" do
  key = Analyzer::Cfml::Pure::COMPONENTS_ONLY_OPTION

  it "sets the flag when a CFML framework owns the routes" do
    options = create_test_options
    apply_cfml_components_only!(options, ["cfml_pure", "cfml_coldbox"])
    any_to_bool(options[key]?).should be_true
  end

  # The regression this function exists to prevent. The flag is written into
  # the caller's options hash and nothing clears it, so an embedder reusing
  # one hash across two scans used to carry the first scan's narrowing into
  # the second — silently dropping the whole `.cfm` page surface of a
  # plain-CFML app that happened to be scanned after a ColdBox one.
  it "clears a previous pass's flag when the next scan does not narrow" do
    options = create_test_options

    apply_cfml_components_only!(options, ["cfml_pure", "cfml_coldbox"])
    any_to_bool(options[key]?).should be_true

    apply_cfml_components_only!(options, ["cfml_pure"])
    any_to_bool(options[key]?).should be_false
  end

  it "leaves the flag false for a scan with no CFML techs at all" do
    options = create_test_options
    apply_cfml_components_only!(options, ["php_laravel"])
    any_to_bool(options[key]?).should be_false
  end

  # `Analyzer#option_flag?` reads it through `any_to_bool`, which maps a
  # missing key and an explicit `false` to the same answer — so writing
  # `false` is a real clear, not just a different spelling of "absent".
  it "writes a value the analyzer layer reads as false" do
    options = create_test_options
    apply_cfml_components_only!(options, ["cfml_pure"])
    options.has_key?(key).should be_true
    any_to_bool(options[key]).should be_false
  end
end
