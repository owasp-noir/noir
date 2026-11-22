require "../../spec_helper"

# Include overloads and forwarding APIs. An existing helper with a short name
# such as "scan" is identified by its file because other scans read directories.
private module TextHelperBoundary
  DEFINITION = /\A(?:(?:private|protected|abstract)\s+)*def\s+(?:self\.)?(\w+[?!]?)(?:\s|\(|:|$)/
  AMBIGUOUS  = %w[scan visible handler_params route_arguments call_arguments]

  def self.conventional?(name : String) : Bool
    return false if name.ends_with?('?') || name.ends_with?('!')
    name.matches?(/\A(?:strip|mask|blank|remove|without)_(?:\w+_)?(?:comments?|strings?|literals?|heredocs?)(?:_with_state|_and_strings)?\z/) ||
      name.matches?(/\A(?:find_|skip_)?matching_(?:\w+_)?(?:delimiter|paren|brace|bracket)(?:_at_byte)?\z/) ||
      name.matches?(/\A(?:extract_balanced(?:_\w+)?|(?:split_(?:\w+_)?top_level|split_top)(?:_\w+)?|split_(?:\w+_)?(?:args|arguments)|top_level_(?:args|arguments|plus_parts|statements)|visible_(?:java|kotlin)_code)\z/)
  end
end

describe "text helper boundary" do
  it "keeps comment stripping, delimiter matching and top-level splitting in shared scanners" do
    inventory = File.read_lines(File.join(__DIR__, "text_helper_signatures.txt"))
      .reject { |line| line.empty? || line.starts_with?('#') }
    allowed = inventory.tally
    names = Set(String).new
    scoped = Set(Tuple(String, String)).new
    inventory.each do |entry|
      file, _, signature = entry.partition(": ")
      name = TextHelperBoundary::DEFINITION.match!(signature)[1]
      if TextHelperBoundary::AMBIGUOUS.includes?(name)
        scoped << {file, name}
      else
        names << name
      end
    end

    sources = Dir.glob("src/**/*.cr")
    sources.size.should be > 200
    unexpected = [] of String
    sources.each do |file|
      File.read_lines(file).each_with_index(1) do |line, number|
        signature = line.strip
        next unless match = TextHelperBoundary::DEFINITION.match(signature)
        name = match[1]
        next unless names.includes?(name) || scoped.includes?({file, name}) || TextHelperBoundary.conventional?(name)

        entry = "#{file}: #{signature}"
        if allowed.fetch(entry, 0) > 0
          allowed[entry] -= 1
        else
          unexpected << "#{file}:#{number}: #{signature}"
        end
      end
    end

    stale = allowed.select { |_, remaining| remaining > 0 }.keys
    fail "Use the shared text helpers:\n#{unexpected.join("\n")}" unless unexpected.empty?
    fail "Remove stale text helper entries:\n#{stale.join("\n")}" unless stale.empty?
  end
end
