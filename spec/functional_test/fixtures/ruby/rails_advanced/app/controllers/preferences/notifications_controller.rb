class Preferences::NotificationsController < Preferences::BaseController
  private

  def after_update_redirect_path
    preferences_notifications_path
  end
end
