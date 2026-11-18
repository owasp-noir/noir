class Accounts::PasswordsController < Devise::PasswordsController
  def create
    super do |resource|
      flash[:notice] = "check your inbox" if resource.errors.empty?
    end
  end

  def update
    reset_with_token
  end

  private

  def reset_with_token
    self.resource = resource_class.reset_password_by_token(resource_params)
    respond_with resource
  end
end
