class Admin::StatusPolicy < ApplicationPolicy
  def review?
    role.can?(:manage_taxonomies)
  end
end
