require "../src/utils/*"

describe "remove_start_slash" do
  it "with slash" do
    remove_start_slash("/abcd/1234").should eq("abcd/1234")
  end
  it "without slash" do
    remove_start_slash("abcd/1234").should eq("abcd/1234")
  end
end
