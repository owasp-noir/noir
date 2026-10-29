class ApplicationController < ActionController::Base
  before_action :block_if_requires_login

  def self.requires_login(arg = {})
    @requires_login_arg = arg
  end

  def self.requires_login_arg
    @requires_login_arg
  end

  def block_if_requires_login
    if arg = self.class.requires_login_arg
      ensure_logged_in
    end
  end

  def ensure_logged_in
    head :unauthorized if current_user.blank?
  end
end
