require "../../spec_helper"

# The inventory is a ratchet. Remove each entry as its caller moves to
# CodeLocator, or when the caller is deleted. Match statements rather than
# whole files so a new read in a legacy caller fails too.
describe "scan source boundary" do
  it "keeps raw file reads and walks behind the scan registry" do
    direct_io = /(?<![\w.])(?:File\.(?:open|read|read_lines|each_line)|(?:Noir::)?TextFile\.read|Dir\.(?:glob|children|each_child|entries)|glob_under)\b/
    sources = Dir.glob("src/**/*.cr")
    sources.size.should be > 200
    allowed = File.read_lines(File.join(__DIR__, "scan_source_io.txt")).tally
    unexpected = [] of String
    sources.each do |path|
      File.read_lines(path).each_with_index(1) do |line, number|
        statement = line.strip
        next if statement.starts_with?('#') || !statement.matches?(direct_io)
        entry = "#{path}: #{statement}"
        if (remaining = allowed[entry]?) && remaining > 0
          allowed[entry] = remaining - 1
        else
          unexpected << "#{path}:#{number}: #{statement}"
        end
      end
    end
    stale = allowed.select { |_, remaining| remaining > 0 }.keys
    fail "Use CodeLocator#read_source or a file index for scan inputs. Unexpected I/O:\n#{unexpected.join("\n")}" unless unexpected.empty?
    fail "Remove stale I/O exceptions:\n#{stale.join("\n")}" unless stale.empty?
  end
end
