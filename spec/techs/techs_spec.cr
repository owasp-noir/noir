require "../../src/techs/techs"

describe "Similar to tech" do
  it "basic" do
    NoirTechs.similar_to_tech("rails").should eq "ruby_rails"
  end

  it "basic2" do
    NoirTechs.similar_to_tech("ruby-rails").should eq "ruby_rails"
  end

  it "Upper case" do
    NoirTechs.similar_to_tech("Rails").should eq "ruby_rails"
  end

  it "False case" do
    NoirTechs.similar_to_tech("Noir").should_not eq "ruby_rails"
  end
end

describe "Get Techs" do
  techs = NoirTechs.get_techs
  techs.each do |k, v|
    it "#{k} in techs" do
      v.should_not be_empty
    end
  end
end
