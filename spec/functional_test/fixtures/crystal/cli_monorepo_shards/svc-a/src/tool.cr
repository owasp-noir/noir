require "option_parser"

# Same file stem in both shards, so both programs infer the binary name
# `tool`. The shard.yml above each one is what tells them apart.
OptionParser.parse do |parser|
  parser.on("--only-a", "a") { }
end
