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

    it "loads a single-matcher rule omitting matchers-condition" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: single-matcher-rule
          info:
            name: Single Matcher Rule
            author: [me]
            severity: low
            description: A test rule without matchers-condition
            reference: []
          matchers:
            - type: word
              patterns:
                - test
              condition: or
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        rules[0].id.should eq("single-matcher-rule")
        rules[0].matchers_condition.should eq("or")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "loads a rule with uppercase condition: OR" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: upper-or-rule
          info:
            name: Upper OR Rule
            author: [me]
            severity: low
            description: A test rule with uppercase condition
            reference: []
          matchers-condition: OR
          matchers:
            - type: WORD
              patterns:
                - test
              condition: OR
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        rules[0].id.should eq("upper-or-rule")
        rules[0].matchers_condition.should eq("or")
        rules[0].matchers[0].condition.should eq("or")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "skips an invalid rule with mistyped matcher type (e.g. keyword)" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: invalid-type-rule
          info:
            name: Invalid Type Rule
            author: [me]
            severity: low
            description: A test rule with invalid matcher type
            reference: []
          matchers-condition: and
          matchers:
            - type: keyword
              patterns:
                - test
              condition: or
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "skips an invalid rule with mistyped matcher condition" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: invalid-condition-rule
          info:
            name: Invalid Condition Rule
            author: [me]
            severity: low
            description: A test rule with invalid condition
            reference: []
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - test
              condition: xor
          category: info
          techs:
            - '*'
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end
  end
end
