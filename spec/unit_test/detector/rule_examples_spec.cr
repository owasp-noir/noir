require "../../spec_helper"
require "../../../src/detector/detector"

describe "detector rule examples" do
  registry = build_detector_list(create_test_options).index_by(&.name)
  Noir::DetectorRules.each_definition do |name, rule|
    detector = registry[rule["key"].as_s]
    examples = rule["examples"]
    Noir::DetectorRules.check_keys(examples, %w[match no_match applicable inapplicable])

    describe name do
      %w[match no_match].each do |group|
        cases = examples[group].as_a
        cases.each_with_index(1) do |sample, index|
          Noir::DetectorRules.check_keys(sample, %w[path content])
          path = sample["path"].as_s
          it "#{group} #{index} (#{path})" do
            detector.applicable?(path).should be_true if group == "match"
            detector.detect(path, sample["content"].as_s).should eq(group == "match")
          end
        end
      end

      %w[applicable inapplicable].each do |group|
        next unless paths = examples[group]?
        paths.as_a.each do |path|
          it "#{group} (#{path})" do
            detector.applicable?(path.as_s).should eq(group == "applicable")
          end
        end
      end
    end
  end
end
