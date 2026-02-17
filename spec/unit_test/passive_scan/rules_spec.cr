require "../../spec_helper"
require "../../../src/passive_scan/rules"
require "../../../src/models/logger"
require "../../../src/utils/utils"
require "file_utils"
require "yaml"

describe NoirPassiveScan do
  describe ".load_rules" do
    it "loads valid rules" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        valid_yaml = <<-YAML
          id: test-rule
          info:
            name: Test Rule
            author:
              - me
            severity: low
            description: A test rule
            reference: []
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - test
              condition: or
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), valid_yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        rules[0].id.should eq("test-rule")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "ignores malformed yaml" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        invalid_yaml = "invalid: yaml: content:"
        File.write(File.join(temp_dir, "invalid.yaml"), invalid_yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "ignores invalid rule structure (missing fields)" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        # Missing matchers
        invalid_structure = <<-YAML
          id: test-rule
          info:
            name: Test Rule
            author:
              - me
            severity: low
            description: A test rule
            reference: []
          matchers-condition: and
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "incomplete.yaml"), invalid_structure)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "loads rules recursively" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        subdir = File.join(temp_dir, "subdir")
        Dir.mkdir(subdir)

        valid_yaml = <<-YAML
          id: recursive-rule
          info:
            name: Recursive Rule
            author:
              - me
            severity: low
            description: A recursive test rule
            reference: []
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - test
              condition: or
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(subdir, "recursive.yaml"), valid_yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        rules[0].id.should eq("recursive-rule")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "ignores non-yaml files" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        File.write(File.join(temp_dir, "test.txt"), "some content")

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end
  end
end
