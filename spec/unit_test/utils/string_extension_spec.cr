require "../../../src/utils/*"

describe "gsub_repeatedly" do
  it "basic" do
    "ab//cd".gsub_repeatedly("//", "/").should eq("ab/cd")
  end

  it "bulk" do
    "ab//////cd".gsub_repeatedly("//", "/").should eq("ab/cd")
  end

  it "origin blank case" do
    "".gsub_repeatedly("//", "/").should eq("")
  end

  it "pattern blank case" do
    "/abcd".gsub_repeatedly("", "").should eq("/abcd")
  end
end
