require "../models/passive_scan"
require "../models/logger"
require "yaml"

module NoirPassiveScan
  def self.load_rules(path : String, logger : NoirLogger) : Array(PassiveScan)
    rules = [] of PassiveScan

    # Read all .yml and .yaml files from the specified path
    Dir.glob("#{escape_glob_path(path)}/**/*.{yml,yaml}").each do |file|
      begin
        # Deserialize each file into a PassiveScan object
        yaml_rule = YAML.parse(File.read(file))
        passive_rule = PassiveScan.new(yaml_rule)
        if passive_rule.valid?
          rules << passive_rule
        else
          # Surface at warning level: a silently-skipped custom rule looks
          # identical to "rule applied" to the user, so a typo'd rule file
          # yields invisible zero coverage.
          logger.warning "Skipped invalid passive rule: #{file}"
        end
      rescue e : Exception
        # Deserialization failure (malformed YAML / missing fields).
        logger.warning "Failed to load passive rule #{file}: #{e.message}"
      end
    end

    logger.sub "└── Loaded #{rules.size} valid passive scan rules."

    rules
  end
end
