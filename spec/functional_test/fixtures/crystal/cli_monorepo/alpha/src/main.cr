require "option_parser"

# Two unrelated programs in one checkout. Neither directory carries a
# shard.yml, so the binary name can only come from the tree: the immediate
# parent (`src`) is shared, the one above it is not.
OptionParser.parse do |parser|
  parser.on("--alpha-only", "alpha") { }
end
