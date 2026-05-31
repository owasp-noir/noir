require "../../spec_helper"
require "../../../src/techs/techs"
require "../../../src/tagger/tagger"

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
  techs = NoirTechs.techs
  techs.each do |k, v|
    it "#{k} in techs" do
      v.should_not be_empty
    end
  end
end

describe "Context support metadata" do
  it "marks functional callee coverage separately from generic AI context buckets" do
    NoirTechs.context_supported?("js_express", "callee").should be_true
    NoirTechs.context_supported?("go_pocketbase", "callee").should be_true
    NoirTechs.context_supported?("js_express", "guards").should be_true
    NoirTechs.context_supported?("js_express", "sinks").should be_true
    NoirTechs.context_supported?("js_express", "validators").should be_true
    NoirTechs.context_supported?("js_express", "signals").should be_true
  end

  it "keeps specification imports out of source-analysis context support" do
    NoirTechs.context_supported?("oas3", "callee").should be_false
    NoirTechs.context_supported?("oas3", "sinks").should be_false
    NoirTechs.context_supported?("oas3", "signals").should be_false
  end

  it "marks every framework auth tagger target as guard-supported" do
    target_techs = NoirTaggers.framework_taggers.values.flat_map do |tagger|
      tagger[:runner].target_techs
    end.uniq!

    target_techs.each do |tech|
      NoirTechs.context_supported?(tech, "guards").should be_true
    end
  end
end
