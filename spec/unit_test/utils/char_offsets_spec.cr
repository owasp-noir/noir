require "spec"
require "../../../src/utils/char_offsets"

describe Noir::CharOffsets do
  ["plain ascii\nRoute::get('/a');\n  x", "// 한글 주석 😀\nRoute::get('/경로');\n  x"].each do |content|
    it "answers like the char-indexed String API (#{content.ascii_only? ? "ASCII" : "non-ASCII"})" do
      offsets = Noir::CharOffsets.new(content)
      (0..content.size).each do |i|
        offsets.char(offsets.byte(i)).should eq(i)
        offsets.line(i).should eq(content[0, i].count('\n') + 1)
        offsets.ascii_whitespace?(i).should eq(content[i]?.try(&.ascii_whitespace?) || false)
      end
      offsets.slice(3, 12).should eq(content[3...12])

      m = offsets.match(/get\('([^']+)'/, 2).should_not be_nil
      plain = content.match!(/get\('([^']+)'/, 2)
      {offsets.begin(m), offsets.end(m), m[1]}.should eq({plain.begin(0), plain.end(0), plain[1]})
      offsets.match(/\Gx/, content.size - 1).should_not be_nil
    end
  end
end
