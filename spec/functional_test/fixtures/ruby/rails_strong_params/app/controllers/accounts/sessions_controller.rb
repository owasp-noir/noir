class Accounts::SessionsController < Devise::SessionsController
  def create
    redirect_to "/login", alert: "single sign-on only"
  end
end
