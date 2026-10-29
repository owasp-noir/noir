class SubscriptionPolicy < ApplicationPolicy
  def index?
    role.can?(:manage_settings)
  end

  alias purge? index?
end
