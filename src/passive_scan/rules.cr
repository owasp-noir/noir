require "../models/passive_scan"
require "../models/logger"
require "yaml"

module NoirPassiveScan
  def self.load_rules(path : String, logger : NoirLogger) : Array(PassiveScan)
    rules = [] of PassiveScan

    # Read all .yml and .yaml files from the specified path. Sorted so the
    # load order — and therefore which of two same-id rules wins in
    # `reject_duplicate_ids` — does not depend on the order the filesystem
    # happens to hand back.
    Dir.glob("#{escape_glob_path(path)}/**/*.{yml,yaml}").sort!.each do |file|
      # `parse_all`, not `parse`: a rule file may hold several `---`
      # separated documents. `YAML.parse` returns only the first one, so
      # every rule after the first `---` in a multi-document file was
      # dropped without a word — a silent hole in the rule set that looks
      # exactly like a clean scan.
      documents = YAML.parse_all(File.read(file))
      if documents.empty?
        logger.warning "Skipped empty passive rule file: #{file}"
        next
      end

      documents.each_with_index do |yaml_rule, doc_index|
        label = documents.size > 1 ? "#{file} (document #{doc_index + 1})" : file
        passive_rule = PassiveScan.new(yaml_rule)
        errors = passive_rule.validation_errors
        if errors.empty?
          # A rule that still fires but lost a matcher to a broken regex
          # keeps working with reduced coverage; say so rather than
          # quietly running a narrower rule than the file describes.
          passive_rule.load_warnings.each do |warning|
            logger.warning "Passive rule '#{passive_rule.id}' in #{label}: #{warning}"
          end
          rules << passive_rule
        else
          # Surface at warning level: a silently-skipped custom rule looks
          # identical to "rule applied" to the user, so a typo'd rule file
          # yields invisible zero coverage. The reasons ride along with the
          # file name — they used to go to Crystal's global `Log`, which
          # writes to STDOUT and so corrupted `-f json` / `-f sarif`.
          logger.warning "Skipped invalid passive rule: #{label} (#{errors.join("; ")})"
        end
      end
    rescue e : Exception
      # Deserialization failure (malformed YAML / unreadable file).
      logger.warning "Failed to load passive rule #{file}: #{e.message}"
    end

    rules = reject_duplicate_ids(rules, logger)

    if rules.empty?
      # Not a `sub` line. `initialize_rules` accepts any non-empty directory,
      # so a half-finished clone or a mis-pointed `--passive-scan-path` loads
      # nothing — and a passive scan with no rules produces the same empty
      # `passive_results` as a codebase with nothing to find. A security scan
      # that ran zero rules is not a clean result; `NoirRunner#detect` also
      # records it so `--strict` can act on it.
      logger.warning "Loaded 0 valid passive scan rules from #{path} — no passive findings can be reported."
    else
      logger.sub "└── Loaded #{rules.size} valid passive scan rules."
    end

    rules
  end

  # Keep the first rule for each `id` and drop the rest.
  #
  # A rule id is the finding's identity: it is what `-f json` reports, what
  # SARIF uses as `ruleId`, and what a CI gate suppresses on. Two rules
  # sharing an id therefore emitted two findings for the same line under the
  # same id (SARIF then described both with whichever rule's metadata was
  # seen first), and nothing said the rule set was inconsistent. This is also
  # what deduplicates a repeated `--passive-scan-path`, which used to double
  # every finding.
  def self.reject_duplicate_ids(rules : Array(PassiveScan), logger : NoirLogger) : Array(PassiveScan)
    return rules if rules.size < 2

    seen = Set(String).new
    rules.select do |rule|
      if seen.add?(rule.id)
        true
      else
        logger.warning "Skipped duplicate passive rule id #{rule.id.inspect} ('#{rule.info.name}') — a rule with that id is already loaded."
        false
      end
    end
  end
end
