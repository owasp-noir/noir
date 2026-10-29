class Admin::SubscriptionsController < ApplicationController
  def index
    authorize :subscription, :index?
  end

  def purge
    authorize :subscription, :purge?
    Subscription.delete_all
  end

  def review
    authorize [:admin, :status], :review?
    Subscription.update_all(reviewed: true)
  end
end
