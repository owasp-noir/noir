require "../../../spec_helper"
require "../../../../src/detector/detectors/php/*"

# The `use Vendor\...;` import probes in these detectors once read
# `(?:^|\n|<\?php\s+)\s*use`: the overlapping `\s+`/`\s*` and a `\s*` run
# started at every newline made whitespace-heavy files quadratic (a 50 KB file
# of spaces took ~10s per detector).
describe "PHP detector use-import probes" do
  options = create_test_options
  detectors = [
    Detector::Php::Symfony.new(options),
    Detector::Php::Laminas.new(options),
    Detector::Php::Yii.new(options),
    Detector::Php::Hyperf.new(options),
    Detector::Php::Phalcon.new(options),
    Detector::Php::ThinkPHP.new(options),
  ]

  it "stays linear on whitespace-padded files" do
    inputs = ["<?php" + " " * 50_000 + ";", "<?php" + " \n" * 20_000 + ";"]
    detectors.each do |detector|
      inputs.each do |content|
        result = false
        elapsed = Time.measure { result = detector.detect("src/a.php", content) }
        result.should be_false
        elapsed.should be < 1.second
      end
    end
  end

  it "still matches imports after blank lines and indentation" do
    content = "<?php\n\n\n    use Symfony\\Component\\HttpFoundation\\Response;\n"
    detectors[0].detect("src/a.php", content).should be_true
    detectors[0].detect("src/a.php", "<?php\tuse Symfony\\Foo;").should be_true
  end
end
