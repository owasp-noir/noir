require "../../spec_helper"

# Ratchet by definition (including overloads), never by whole file. Remove
# entries when callers adopt Noir::FileRole. Do not add new exceptions.
describe "file role boundary" do
  it "keeps new file-role predicates in the shared classifier" do
    allowed = File.read_lines(File.join(__DIR__, "file_role_predicates.txt")).tally
    unexpected = [] of String
    sources = Dir.glob("src/**/*.cr")
    sources.size.should be > 200
    sources.each do |file|
      next if file == "src/models/file_role.cr"
      File.read_lines(file).each_with_index(1) do |line, number|
        signature = line.strip
        match = /\A(?:(?:private|protected|abstract)\s+)*def\s+(?:self\.)?(\w+)\?/.match(signature)
        next unless match
        name = match[1]
        file_gate = name.matches?(/path|file|dir|tree|source/) && name.matches?(/test|example|vendor|fixture|mock|stub|generated|non_production|benchmark|sample/)
        next unless file_gate || {"test_stub_only", "generated_client_spec", "storybook_story"}.includes?(name)
        entry = "#{file}: #{signature}"
        if allowed.fetch(entry, 0) > 0
          allowed[entry] -= 1
        else
          unexpected << "#{file}:#{number}: #{signature}"
        end
      end
    end

    stale = allowed.select { |_, count| count > 0 }.keys
    fail "Use Noir::FileRole for new file gates:\n#{unexpected.join("\n")}" unless unexpected.empty?
    fail "Remove stale file-role exceptions:\n#{stale.join("\n")}" unless stale.empty?
  end
end
