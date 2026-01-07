require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Php Pure" do
  options = create_test_options
  instance = Detector::Php::Php.new options

  it "detect_php 1" do
    instance.detect("1.php", "<? phpinfo(); ?>").should be_true
  end

  it "detect_php 2" do
    instance.detect("admin.php", "<?php TITLE!!! ?>").should be_true
  end

  it "detect_php 3" do
    instance.detect("admin.js", "<? This is template ?>").should_not be_true
  end
end
