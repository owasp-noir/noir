require "../../../spec_helper"
require "../../../../src/detector/detectors/java/*"

describe "Detect Java JSP" do
  options = create_test_options
  instance = Detector::Java::Jsp.new options

  it "case1" do
    instance.detect("1.jsp", "<% info(); %>").should be_true
  end
end
