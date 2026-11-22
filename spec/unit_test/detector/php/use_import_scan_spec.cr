require "../../../spec_helper"
require "../../../../src/detector/detector"

# The `use Vendor\...;` import probes in these detectors once read
# `(?:^|\n|<\?php\s+)\s*use`: the overlapping `\s+`/`\s*` and a `\s*` run
# started at every newline made whitespace-heavy files quadratic (a 50 KB file
# of spaces took ~10s per detector).
describe "PHP detector use-import probes" do
  registry = build_detector_list(create_test_options).index_by(&.name)
  detectors = %w[php_symfony php_laminas php_yii php_hyperf php_phalcon php_thinkphp].map { |key| registry[key] }

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
