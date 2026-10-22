require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

describe "Detect Nextcloud" do
  options = create_test_options
  instance = Detector::Php::Nextcloud.new options

  it "detects an app's appinfo/info.xml" do
    xml = %(<info><id>notes</id><dependencies><nextcloud min-version="28" max-version="31"/></dependencies></info>)
    instance.detect("notes/appinfo/info.xml", xml).should be_true
  end

  it "detects app framework imports" do
    instance.detect("lib/Controller/NoteController.php", "<?php\nuse OCP\\AppFramework\\Controller;").should be_true
  end

  it "does not detect unrelated info.xml or PHP" do
    instance.detect("docs/info.xml", %(<nextcloud/>)).should be_false
    instance.detect("appinfo/info.xml", %(<info><id>x</id></info>)).should be_false
    instance.detect("index.php", "<?php echo 'hi';").should be_false
  end
end
