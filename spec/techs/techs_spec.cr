require "../../src/techs/techs"

describe "Similar to tech" do
  it "true" do
    NoirTechs.similar_to_tech("rails").should eq "ruby_rails"
  end
end