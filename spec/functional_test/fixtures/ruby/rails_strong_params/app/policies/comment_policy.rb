class CommentPolicy < ApplicationPolicy
  def permitted_attributes_for_create
    %i[body parent_id]
  end

  def permitted_attributes
    %i[body]
  end
end
