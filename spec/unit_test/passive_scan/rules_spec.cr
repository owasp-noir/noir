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

    it "loads every document of a multi-document rule file" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        # `YAML.parse` stops at the first document, so every rule after the
        # first `---` used to be dropped with no message at all.
        yaml = <<-YAML
          ---
          id: doc-one
          info: {name: Doc One, author: [me], severity: low, description: ., reference: []}
          matchers-condition: or
          matchers:
            - type: word
              patterns: [DOCONE]
              condition: or
          category: info
          techs: ['*']
          ---
          id: doc-two
          info: {name: Doc Two, author: [me], severity: low, description: ., reference: []}
          matchers-condition: or
          matchers:
            - type: word
              patterns: [DOCTWO]
              condition: or
          category: info
          techs: ['*']
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.map(&.id).sort.should eq(["doc-one", "doc-two"])
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "keeps only the first rule for a duplicated id" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        rule = ->(name : String) do
          <<-YAML
            id: same-id
            info: {name: #{name}, author: [me], severity: low, description: ., reference: []}
            matchers-condition: or
            matchers:
              - type: word
                patterns: [NEEDLE]
                condition: or
            category: info
            techs: ['*']
            YAML
        end

        File.write(File.join(temp_dir, "a.yaml"), rule.call("First"))
        File.write(File.join(temp_dir, "b.yaml"), rule.call("Second"))

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        # Load order is sorted by path, so `a.yaml` wins deterministically.
        rules[0].info.name.should eq("First")
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "skips a rule whose only matcher's regex cannot compile" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: dead-regex-rule
          info: {name: Dead Regex, author: [me], severity: low, description: ., reference: []}
          matchers-condition: or
          matchers:
            - type: regex
              patterns:
                - "[unterminated"
              condition: or
          category: info
          techs: ['*']
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        # A rule that can never fire used to be counted among the "valid"
        # rules, so a typo'd pattern read exactly like a clean scan.
        rules.size.should eq(0)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "keeps an or-rule that still has one compiling matcher" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: partial-regex-rule
          info: {name: Partial Regex, author: [me], severity: low, description: ., reference: []}
          matchers-condition: or
          matchers:
            - type: regex
              patterns:
                - "[unterminated"
              condition: or
            - type: word
              patterns: [NEEDLE]
              condition: or
          category: info
          techs: ['*']
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        rules.size.should eq(1)
        rules[0].load_warnings.size.should eq(1)
      ensure
        FileUtils.rm_rf(temp_dir)
      end
    end

    it "skips an and-rule with one dead matcher" do
      temp_dir = File.tempname
      Dir.mkdir(temp_dir)
      begin
        yaml = <<-YAML
          id: and-dead-rule
          info: {name: And Dead, author: [me], severity: low, description: ., reference: []}
          matchers-condition: and
          matchers:
            - type: regex
              patterns:
                - "[unterminated"
              condition: or
            - type: word
              patterns: [NEEDLE]
              condition: or
          category: info
          techs: ['*']
          YAML

        File.write(File.join(temp_dir, "rule.yaml"), yaml)

        logger = NoirLogger.new(false, false, false, true)
        rules = NoirPassiveScan.load_rules(temp_dir, logger)

        # Under `and` every matcher has to hit, so one dead matcher makes
        # the whole rule unable to fire.
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
