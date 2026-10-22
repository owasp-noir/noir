require "spec"
require "../../../src/utils/file_extension"

describe Noir::FileExtension do
  it "folds the case of Windows-origin extensions only" do
    Noir::FileExtension.fold("a/B/P.ASPX").should eq("a/B/P.aspx")
    Noir::FileExtension.fold("LOGIN.Asp").should eq("LOGIN.asp")
    Noir::FileExtension.fold("Program.CS").should eq("Program.cs")
  end

  it "returns the same string for everything else" do
    ["a/login.asp", "a/Gemfile", "A.B/Makefile", "Makefile.PL", "Build.PL", "x.C", "x.H", "plumber.R", "APP.PY"].each do |path|
      Noir::FileExtension.fold(path).should be(path)
    end
  end

  it "keys the extension index the same way" do
    Noir::FileExtension.index_key(".ASPX").should eq(".aspx")
    Noir::FileExtension.index_key(".PL").should eq(".PL")
    Noir::FileExtension.index_key(".C").should eq(".C")
  end
end
