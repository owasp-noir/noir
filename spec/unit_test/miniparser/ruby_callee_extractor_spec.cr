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
end
