# Shared by macro helpers that embed the YAML shipped with Noir.
module CompileTimeYaml
  def self.map(dir : String, &)
    # A glob interprets backslashes in Windows directory names as escapes.
    names = Dir.children(dir).select { |name| name.ends_with?(".yml") || name.ends_with?(".yaml") }.sort!
    names.map { |name| yield name, File.read(File.join(dir, name)) }
  end
end
