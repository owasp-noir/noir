require "../../../src/detector/detectors/*"

describe "Detect Java JSP" do
  options = default_options()
  instance = DetectorJavaJsp.new options

  it "case1" do
    instance.detect("1.jsp", "<% info(); %>").should eq(true)
  end
end
