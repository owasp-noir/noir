require "spec"
require "../../../src/utils/ruby_inflector"

describe Noir::RubyInflector do
  describe ".singularize" do
    it "leaves an uncountable word as it is" do
      Noir::RubyInflector.singularize("news").should eq("news")
      Noir::RubyInflector.singularize("series").should eq("series")
      Noir::RubyInflector.singularize("equipment").should eq("equipment")
    end

    it "matches an uncountable word only as the whole tail of a name" do
      Noir::RubyInflector.singularize("breaking_news").should eq("breaking_news")
      # `fish` is uncountable, `catfishes` is a regular `-es` plural.
      Noir::RubyInflector.singularize("catfishes").should eq("catfish")
    end

    it "applies the irregular plurals" do
      Noir::RubyInflector.singularize("people").should eq("person")
      Noir::RubyInflector.singularize("men").should eq("man")
      Noir::RubyInflector.singularize("children").should eq("child")
    end

    it "applies an irregular plural to the tail of a snake_case name" do
      Noir::RubyInflector.singularize("team_people").should eq("team_person")
      Noir::RubyInflector.singularize("grandchildren").should eq("grandchild")
    end

    it "drops the doubled z of -zzes" do
      Noir::RubyInflector.singularize("quizzes").should eq("quiz")
    end

    it "drops -es after a sibilant ending" do
      Noir::RubyInflector.singularize("boxes").should eq("box")
      Noir::RubyInflector.singularize("statuses").should eq("status")
      Noir::RubyInflector.singularize("aliases").should eq("alias")
      Noir::RubyInflector.singularize("buses").should eq("bus")
      Noir::RubyInflector.singularize("addresses").should eq("address")
      Noir::RubyInflector.singularize("branches").should eq("branch")
      Noir::RubyInflector.singularize("dishes").should eq("dish")
    end

    it "turns -ies into -y after a consonant or qu" do
      Noir::RubyInflector.singularize("categories").should eq("category")
      Noir::RubyInflector.singularize("queries").should eq("query")
    end

    it "turns -ta and -ia into -um" do
      Noir::RubyInflector.singularize("media").should eq("medium")
      Noir::RubyInflector.singularize("data").should eq("datum")
    end

    it "drops a plain trailing s" do
      Noir::RubyInflector.singularize("users").should eq("user")
      Noir::RubyInflector.singularize("days").should eq("day")
    end

    it "singularizes only the tail of a snake_case name" do
      Noir::RubyInflector.singularize("scheduled_statuses").should eq("scheduled_status")
      Noir::RubyInflector.singularize("users_groups").should eq("users_group")
    end

    it "keeps a word that is already singular" do
      Noir::RubyInflector.singularize("class").should eq("class")
      Noir::RubyInflector.singularize("user").should eq("user")
      Noir::RubyInflector.singularize("s").should eq("s")
      Noir::RubyInflector.singularize("").should eq("")
    end
  end

  describe ".pluralize" do
    it "turns -y into -ies after a consonant or qu" do
      Noir::RubyInflector.pluralize("policy").should eq("policies")
      Noir::RubyInflector.pluralize("soliloquy").should eq("soliloquies")
    end

    it "keeps -y after a vowel" do
      Noir::RubyInflector.pluralize("day").should eq("days")
    end

    it "adds -es after a sibilant ending" do
      Noir::RubyInflector.pluralize("box").should eq("boxes")
      Noir::RubyInflector.pluralize("status").should eq("statuses")
      Noir::RubyInflector.pluralize("branch").should eq("branches")
      Noir::RubyInflector.pluralize("dish").should eq("dishes")
    end

    it "adds -s otherwise" do
      Noir::RubyInflector.pluralize("project").should eq("projects")
      Noir::RubyInflector.pluralize("scheduled_task").should eq("scheduled_tasks")
    end
  end
end
