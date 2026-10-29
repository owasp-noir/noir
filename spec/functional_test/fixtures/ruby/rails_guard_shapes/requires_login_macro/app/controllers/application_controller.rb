class ApplicationController < ActionController::Base
  def self.requires_login(arg = {})
    before_action :ensure_logged_in, arg
  end

  def ensure_logged_in
    head :unauthorized if current_user.blank?
  end
end
