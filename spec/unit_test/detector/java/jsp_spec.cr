require "../../../../src/detector/detectors/*"

describe "Detect Java JSP" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Java::Jsp.new options

  it "case1" do
    instance.detect("1.jsp", "<% info(); %>").should eq(true)
  end
end
