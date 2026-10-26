class CommentsController < ApplicationController
  def create
    Comment.create(permitted_attributes(Comment))
  end
end
