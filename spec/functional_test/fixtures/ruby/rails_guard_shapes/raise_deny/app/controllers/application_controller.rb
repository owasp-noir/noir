class ApplicationController < ActionController::Base
  def ensure_logged_in
    raise Discourse::NotLoggedIn.new if current_user.blank?
  end

  def ensure_admin
    raise Discourse::InvalidAccess.new unless current_user && current_user.admin?
  end
end
