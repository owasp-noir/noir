require "../../spec_helper"
require "../../../src/utils/text_file"

describe "Noir::TextFile.byte_window" do
  it "returns the bytes asked for when the cut falls between characters" do
    Noir::TextFile.byte_window("abcdef", 1, 3).should eq("bcd")
    Noir::TextFile.byte_window("a가나", 1, 3).should eq("가")
    Noir::TextFile.byte_window("a가나", 1, 6).should eq("가나")
  end

  it "moves a cut inside a multi-byte character back to its start" do
    # 2-, 3- and 4-byte characters, cut after each of their leading bytes.
    {"é" => 2, "가" => 3, "😀" => 4}.each do |char, size|
      (1...size).each do |cut|
        window = Noir::TextFile.byte_window("ab#{char}cd", 0, 2 + cut)
        window.should eq("ab"), "#{char} cut at #{cut}"
        window.valid_encoding?.should be_true
      end
      Noir::TextFile.byte_window("ab#{char}cd", 0, 2 + size).should eq("ab#{char}")
    end
  end

  it "stops at the end of the text" do
    Noir::TextFile.byte_window("ab가", 2, 120).should eq("가")
    Noir::TextFile.byte_window("ab", 2, 8).should eq("")
    Noir::TextFile.byte_window("ab", 5, 8).should eq("")
    Noir::TextFile.byte_window("가", 0, 1).should eq("")
  end

  it "yields a slice a regex can match" do
    text = "x) " + "가" * 60
    Noir::TextFile.byte_window(text, 2, 120).matches?(/\A\s*=>/).should be_false
  end
end
