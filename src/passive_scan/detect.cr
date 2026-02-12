require "../models/passive_scan"
require "../models/logger"
require "./severity"
require "yaml"

module NoirPassiveScan
  # Original detect method for backward compatibility
  def self.detect(file_path : String, file_content : String, rules : Array(PassiveScan), logger : NoirLogger) : Array(PassiveScanResult)
    detect_with_severity(file_path, file_content, rules, logger, "low")
  end

  # Enhanced detect method with severity filtering
  def self.detect_with_severity(file_path : String, file_content : String, rules : Array(PassiveScan), logger : NoirLogger, min_severity : String) : Array(PassiveScanResult)
    results = [] of PassiveScanResult

    rules.each do |rule|
      # Skip rules that don't meet the severity threshold
      unless PassiveScanSeverity.meets_threshold?(rule.info.severity, min_severity)
        next
      end

      matchers = rule.matchers

      if rule.matchers_condition == "and"
        if matchers.all? { |matcher| match_content?(file_content, matcher) }
          logger.sub "└── Detected: #{rule.info.name}"
          index = 0
          file_content.each_line do |line|
            if matchers.all? { |matcher| match_content?(line, matcher) }
              results << PassiveScanResult.new(rule, file_path, index + 1, line)
            end
            index += 1
          end
        end
      else
        matchers.each do |matcher|
          index = 0
          file_content.each_line do |line|
            if match_content?(line, matcher)
              logger.sub "└── Detected: #{rule.info.name}"
              results << PassiveScanResult.new(rule, file_path, index + 1, line)
            end
            index += 1
          end
        end
      end
    end

    results
  end

  private def self.match_content?(content : String, matcher : PassiveScan::Matcher) : (Array(YAML::Any) | Bool)
    case matcher.type
    when "word"
      case matcher.condition
      when "and"
        matcher.patterns && matcher.patterns.all? { |pattern| content.includes?(pattern.to_s) }
      when "or"
        matcher.patterns && matcher.patterns.any? { |pattern| content.includes?(pattern.to_s) }
      else
        false
      end
    when "regex"
      case matcher.condition
      when "and"
        if regexes = matcher.compiled_regexes
          regexes.all? { |regex| content.match(regex) }
        else
          begin
            matcher.patterns && matcher.patterns.all? { |pattern| content.match(Regex.new(pattern.to_s)) }
          rescue
            false
          end
        end
      when "or"
        if regex = matcher.compiled_regex
          begin
            !!content.match(regex)
          rescue
            false
          end
        else
          begin
            matcher.patterns && matcher.patterns.any? { |pattern| content.match(Regex.new(pattern.to_s)) }
          rescue
            false
          end
        end
      else
        false
      end
    else
      false
    end
  end
end
