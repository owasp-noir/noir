require "../../../../src/detector/detectors/*"

describe "Detect Php Pure" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  instance = Detector::Php::Php.new options

  it "detect_php 1" do
    instance.detect("1.php", "<? phpinfo(); ?>").should eq(true)
  end

  it "detect_php 2" do
    instance.detect("admin.php", "<?php TITLE!!! ?>").should eq(true)
  end

  it "detect_php 3" do
    instance.detect("admin.js", "<? This is template ?>").should_not eq(true)
  end
end
