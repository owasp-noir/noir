# Compile-time helper for embedding detector and tagger rule sources.
require "../../compile_time/yaml_files"

entries = CompileTimeYaml.map(ARGV[0]) { |name, source| "{#{name.inspect}, #{source.inspect}}" }
puts "[#{entries.join(", ")}] of Tuple(String, String)"
