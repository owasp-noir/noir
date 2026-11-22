require "../../spec_helper"

# Exceptions are individual signatures, including overloads. Delete an entry
# when its caller adopts Noir::URLPath. Never add one to admit a new helper.
describe "adapter path helper boundary" do
  it "keeps route normalization and placeholder extraction in URLPath" do
    files = Dir.glob("src/analyzer/analyzers/**/*.cr")
    files.size.should be > 200
    definitions = [] of String
    files.each do |file|
      File.read_lines(file).each do |line|
        signature = line.strip
        match = /\A(?:(?:private|protected|abstract)\s+)*def\s+(?:self\.)?(\w+)\b/.match(signature)
        next unless match
        name = match[1]
        normalization = name.matches?(/\A(?:normali[sz]e|convert|rewrite|canonicalize)(?:\z|\w*(?:path|url|route|segment|prefix|placeholder))/)
        extraction = name.matches?(/path_(?:param|var)|(?:param|var)\w*_from_(?:path|url)|\Aextract_route_(?:param|placeholder)/)
        joining = name.matches?(/\A(?:join|combine)\w*(?:path|url|prefix|route)|\A(?:mount|nest|namespace|segment)_join\z/)
        definitions << "#{file}: #{signature}" if normalization || extraction || joining
      end
    end

    allowed = File.read_lines(File.join(__DIR__, "path_helper_signatures.txt")).tally
    unexpected = [] of String
    definitions.each do |entry|
      if allowed.fetch(entry, 0) > 0
        allowed[entry] -= 1
      else
        unexpected << entry
      end
    end
    stale = allowed.select { |_, remaining| remaining > 0 }.keys
    fail "Use Noir::URLPath for new adapter path helpers:\n#{unexpected.join("\n")}" unless unexpected.empty?
    fail "Remove stale path helper exceptions:\n#{stale.join("\n")}" unless stale.empty?
  end
end
