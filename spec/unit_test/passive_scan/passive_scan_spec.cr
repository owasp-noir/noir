require "../../../src/passive_scan/detect.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/passive_scan.cr"

describe NoirPassiveScan do
  it "detects matches with 'and' condition" do
    logger = NoirLogger.new(false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(%(
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: word
            patterns:
              - test
              - content
            condition: and
        category: secret
        techs:
          - '*'
          - ruby-rails
      ))),
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(1)
    results[0].line_number.should eq(1)
  end

  it "detects matches with 'or' condition" do
    logger = NoirLogger.new(false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(%(
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: word
            patterns:
              - test
              - content
            condition: or
        category: secret
        techs:
          - '*'
          - ruby-rails
      ))),
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(2)
    results[0].line_number.should eq(1)
    results[1].line_number.should eq(2)
  end

  it "detects regex matches" do
    logger = NoirLogger.new(false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(%(
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: regex
            patterns:
              - ^This
            condition: or
        category: secret
        techs:
          - '*'
          - ruby-rails
      ))),
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(1)
    results[0].line_number.should eq(1)
  end
end
