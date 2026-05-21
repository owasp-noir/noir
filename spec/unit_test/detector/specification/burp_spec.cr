require "../../../spec_helper"
require "../../../../src/detector/detectors/specification/*"

describe "Detect Burp Sitemap" do
  options = create_test_options
  instance = Detector::Specification::Burp.new options

  it "xml with items root and burpVersion attribute" do
    sample = %(<?xml version="1.0"?><items burpVersion="2024.6"><item></item></items>)
    instance.detect("sitemap.xml", sample).should be_true
  end

  it "rejects xml without burpVersion attribute" do
    sample = %(<?xml version="1.0"?><items><item></item></items>)
    instance.detect("sitemap.xml", sample).should be_false
  end

  it "rejects unrelated xml" do
    instance.detect("config.xml", "<config><items/></config>").should be_false
  end

  it "rejects non-xml filenames" do
    sample = %(<?xml version="1.0"?><items burpVersion="2024.6"></items>)
    instance.detect("sitemap.json", sample).should be_false
  end

  it "code_locator" do
    locator = CodeLocator.instance
    locator.clear "burp-sitemap"
    sample = %(<?xml version="1.0"?><items burpVersion="2024.6"></items>)
    instance.detect("sitemap.xml", sample)
    locator.all("burp-sitemap").should eq(["sitemap.xml"])
  end
end
