require "../../../spec_helper"
require "../../../../src/detector/detectors/python/robyn" # Adjust path as necessary

describe "Unit Test for Detector::Python::Robyn" do
  @detector : Detector::Python::Robyn

  before_each do
    @detector = Detector::Python::Robyn.new
  end

  it "should set the name correctly" do
    @detector.name.should eq("python_robyn")
  end

  describe "detect method" do
    let(filename) { "test_file.py" } # Common filename for tests

    context "Positive Detection Scenarios" do
      it "should return true for 'from robyn import Robyn'" do
        content = "from robyn import Robyn\napp = Robyn()"
        @detector.detect(filename, content).should be_true
      end

      it "should return true for 'import robyn'" do
        content = "import robyn\napp = robyn.Robyn()"
        @detector.detect(filename, content).should be_true
      end

      it "should return true for 'from robyn import Robyn as AnotherName'" do
        content = "from robyn import Robyn as AnotherName\napp = AnotherName()"
        # This works because "from robyn import Robyn" is a substring
        @detector.detect(filename, content).should be_true
      end

      it "should return true for 'import robyn' with surrounding code and whitespace" do
        content = <<-PYTHON
          # Some comments
          import sys
          import robyn

          app = robyn.Robyn()
          # More code
        PYTHON
        @detector.detect(filename, content).should be_true
      end

      it "should return true even if filename is not .py but content matches" do
        # The base Detector class's detect method filters by filename first.
        # However, the Robyn specific class's detect method only receives content.
        # The problem description implies the Robyn class's detect method should be tested.
        # If the base class `detect` is called, it would filter by filename.
        # Let's assume we are unit testing the logic within Robyn#detect(file_contents)
        # which is `file_contents.includes?("from robyn import Robyn") || file_contents.includes?("import robyn")`
        # The actual call from the system would be detector_instance.detect(filename, content)
        # which first checks filename in base class, then calls child's detect(content)
        # For this unit test, we are testing the child's `detect(content_only_arg_if_it_were_public)`
        # or more accurately, ensuring the string matching part works.
        # The detector's `detect` method is `detect(file_contents : String) : Bool` as per instructions.
        # It does not take filename. The base class `Detector` has `detect(filename, content)`
        # So we call the Robyn specific one.

        # Re-reading the prompt:
        # "The detector's detect method also checks if filename.ends_with? ".py".
        # While unit tests primarily focus on file_contents, ensure that the calls to detect in the tests
        # use a .py filename to accurately reflect typical usage. For example, detector.detect("some_file.py", content)."
        # This implies the `detect(filename, content)` of the *base* class is the entry point for testing,
        # which then calls the overridden `detect(file_contents)` if the filename matches.
        # Let's stick to the base class's `detect(filename, content)` signature for the test calls.

        content_py = "import robyn"
        @detector.detect("another.py", content_py).should be_true
      end

    end

    context "Negative Detection Scenarios" do
      it "should return false for non-Robyn imports" do
        content = "from flask import Flask\napp = Flask(__name__)"
        @detector.detect(filename, content).should be_false
      end

      it "should return false for an empty string" do
        content = ""
        @detector.detect(filename, content).should be_false
      end

      it "should return false if 'robyn' is mentioned but not as an import" do
        content = "my_variable = 'robyn_framework_is_great'"
        @detector.detect(filename, content).should be_false
      end

      it "should return false for a common phrase that coincidentally contains 'import robyn'" do
        content = "This is a text that talks about how to import robyn."
        @detector.detect(filename, content).should be_false
      end

      it "should return false if filename is not .py even if content matches" do
        # This tests the base Detector's filename check
        content_txt = "import robyn"
        @detector.detect("test_file.txt", content_txt).should be_false
      end

      it "should return false for 'from robynsomething import X'" do
        content = "from robynsomething import X"
        @detector.detect(filename, content).should be_false
      end

      it "should return false for 'import robynsomething'" do
        content = "import robynsomething"
        @detector.detect(filename, content).should be_false
      end
    end
  end
end
