# Macro helper. Walk YAML nodes directly so repeated keys are still visible.
require "yaml"
require "../compile_time/yaml_files"

private def literal(node : YAML::Nodes::Node) : String
  case node
  when YAML::Nodes::Mapping
    String.build do |io|
      io << "{"
      node.each do |key, value|
        io << ":" << key.as(YAML::Nodes::Scalar).value.inspect << " => " << literal(value) << ",\n"
      end
      io << "}"
    end
  when YAML::Nodes::Sequence
    strings = node.map { |item| item.as(YAML::Nodes::Scalar).value }
    "#{strings.inspect} of String"
  when YAML::Nodes::Scalar
    value = YAML::Schema::Core.parse_scalar(node)
    return value.inspect if value.is_a?(String) || value.is_a?(Bool)
    node.raise("expected a string or boolean")
  else
    node.raise("unsupported catalog node: #{node.kind}")
  end
end

owners = {} of String => String
bundles = CompileTimeYaml.map(ARGV[0]) do |name, source|
  docs = YAML::Nodes.parse_all(source)
  raise "expected one catalog mapping" unless docs.size == 1
  entries = docs.first.nodes.first.as(YAML::Nodes::Mapping)
  String.build do |io|
    entries.each do |key, entry|
      tech = key.as(YAML::Nodes::Scalar).value
      origin = "#{name}:#{key.start_line}"
      if first = owners[tech]?
        raise "duplicate tech key #{tech} at #{origin}, first declared at #{first}"
      end
      owners[tech] = origin
      io << ":" << tech.inspect << " => " << literal(entry.as(YAML::Nodes::Mapping)) << ",\n"
    end
  end
rescue ex
  abort "#{name}: #{ex.message}"
end
puts "{\n#{bundles.join}}"
