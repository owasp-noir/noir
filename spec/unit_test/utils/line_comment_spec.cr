require "spec"
require "../../../src/utils/line_comment"

describe Noir::LineComment do
  it "keeps both quote styles, escaped quotes and the space before a comment" do
    prefix = %q(이름 = "a\"#b" + 'c\'#d'  )
    Noir::LineComment.strip(prefix + "# note", '#').should eq prefix
  end

  it "closes a quote after an escaped backslash and treats a backslash outside quotes as data" do
    prefix = "\"a" + "\\" * 2 + "\""
    Noir::LineComment.strip(prefix + "# note", '#').should eq prefix
    Noir::LineComment.strip(%q(a\# note), '#').should eq "a\\"
  end

  it "keeps unterminated strings on the current line and accepts a different marker" do
    Noir::LineComment.strip(%q('x #), '#').should eq %q('x #)
    Noir::LineComment.strip(%q("x%" % note), '%').should eq %q("x%" )
    Noir::LineComment.strip("#", '#').should eq ""
  end
end
