require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect ZAP Sites Tree" do
  options = create_test_options
  instance = Detector::Specification::ZapSitesTree.new options

  it "detect" do
    content = <<-EOS
    - node: Sites
      children:
      - node: https://www.hahwul.com
    EOS

    instance.detect("sites.yml", content).should be_true
  end

  it "code_locator" do
    content = <<-EOS
    - node: Sites
      children:
      - node: https://www.hahwul.com
    EOS

    locator = CodeLocator.instance
    locator.clear "zap-sites-tree"
    instance.detect("sites.yaml", content)
    locator.all("zap-sites-tree").should eq(["sites.yaml"])
  end
end
