require "../../../../src/detector/detectors/*"

describe "Detect ZAP Sites Tree" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Specification::ZapSitesTree.new options

  it "detect" do
    content = <<-EOS
    - node: Sites
      children:
      - node: https://www.hahwul.com
    EOS

    instance.detect("sites.yml", content).should eq(true)
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
