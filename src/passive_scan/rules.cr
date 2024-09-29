require "../models/passive_scan"
require "../models/logger"
require "yaml"

module NoirPassiveScan
  def self.load_rules(path : String, logger : NoirLogger) : Array(PassiveScan)
    rules = [] of PassiveScan

    # Read all .yml and .yaml files from the specified path
    Dir.glob("#{path}/*.{yml,yaml}").each do |file|
      begin
        # Deserialize each file into a PassiveScan object
        yaml_rule = YAML.parse(File.read(file))
        passive_rule = PassiveScan.new(yaml_rule)
        if passive_rule.valid?
          rules << passive_rule
        else
          logger.debug_sub "Invalid rule in #{file}"
        end
        rules << passive_rule
      rescue e : Exception
        # Log or handle the error if deserialization fails
        logger.debug_sub "Failed to load rule from #{file}: #{e.message}"
      end
    end

    logger.sub "└── Loaded #{rules.size} valid passive scan rules."

    rules
  end
end
