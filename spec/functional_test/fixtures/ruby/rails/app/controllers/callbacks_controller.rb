class CallbacksController < Devise::OmniauthCallbacksController
  def github
    render plain: request.headers["X-Callback-State"]
  end

  def gitlab
    head :ok
  end
end
