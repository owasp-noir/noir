require "../../spec_helper"
require "../../../src/miniparsers/ruby_callee_extractor"

describe Noir::RubyCalleeExtractor do
  it "extracts receiver and bare calls from Ruby handler bodies with line numbers" do
    body = <<-RUBY
      posts = PostQuery.list(params[:page])
      AuditLog.write("index")
      render(json: serialize_posts(posts))
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "posts_controller.rb", 10)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"PostQuery.list", 10},
      {"AuditLog.write", 11},
      {"render", 12},
      {"serialize_posts", 12},
    ])
  end

  it "skips comments and receiver method duplicates" do
    body = <<-RUBY
      # AuditLog.write("ignored")
      @post.save!
      Admin::Health.check()
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "posts_controller.rb", 20)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"@post.save!", 21},
      {"Admin::Health.check", 22},
    ])
  end

  it "extracts Ruby command-style calls without parentheses" do
    body = <<-RUBY
      render json: serialize_posts(posts)
      redirect_to post_url(post)
      head :no_content
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "posts_controller.rb", 30)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"render", 30},
      {"serialize_posts", 30},
      {"redirect_to", 31},
      {"post_url", 31},
      {"head", 32},
    ])
  end

  it "does not extract bare words from string literals" do
    body = <<-RUBY
      format.html { redirect_to post_url(@post), notice: "Post was successfully created." }
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "posts_controller.rb", 40)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"redirect_to", 40},
      {"post_url", 40},
    ])
  end

  it "skips Rails format DSL and simple attribute readers" do
    body = <<-RUBY
      @story.user_id
      story.id
      format.json { render json: story_url(@story) }
      request.remote_ip
      respond_to do |format|
        format.html
      end
      response.status = 204
      @story.save
      @story.valid?
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "stories_controller.rb", 50)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"render", 52},
      {"story_url", 52},
      {"response.status", 57},
      {"@story.save", 58},
      {"@story.valid?", 59},
    ])
  end

  it "reads safe navigation, chains split over lines and calls inside interpolation" do
    body = <<-'RUBY'
      @invitation&.update!(accepted_at: now)
      Current.family
        .entries
        .where(id: ids)
      @title = "#{I18n.t("about.title")} - #{site.name}"
      User.find(id).posts.create(post_params)
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "c.rb", 1)
    callees.map { |name, _, line| {name, line} }.should eq([
      {"@invitation.update!", 1},
      {"Current.family.entries.where", 4},
      {"I18n.t", 5},
      {"User.find", 6},
      {"posts.create", 6},
    ])
  end

  it "takes no callee from word arrays, heredocs, string text or local variables" do
    body = <<-RUBY
      %w[test development].include?(env)
      sql = <<~SQL
        select render(x) from t where a.b(1)
      SQL
      notice = "redirect_to admin_path(x)"
      ex = error
      raise ex if ex
      helper_call if ready?
      RUBY

    callees = Noir::RubyCalleeExtractor.callees_for_body(body, "c.rb", 1)
    callees.map(&.[0]).should eq(["raise", "helper_call"])
  end

  it "reads a body whose heredocs were blanked out by the non-code mask" do
    body = "sql = <<~SQL\n\n\nrender json: rows\n"
    Noir::RubyCalleeExtractor.callees_for_body(body, "c.rb", 1).map(&.[0]).should eq(["render"])
  end

  it "ends each method at its own `end`, whatever its body holds" do
    source = <<-RUBY
      class PostsController < ApplicationController
        def index
          sql = <<~SQL
            end
          SQL
          Post.where(sql)
        end

        private def helper
          AuditLog.write(1) if x.y.z
        end
      end
      RUBY

    by_method = Noir::RubyCalleeExtractor.callees_by_method(source, "posts_controller.rb")
    by_method["index"].map { |name, _, line| {name, line} }.should eq([{"Post.where", 6}])
    by_method["helper"].map(&.[0]).should eq(["AuditLog.write", "x.y.z"])
  end
end
