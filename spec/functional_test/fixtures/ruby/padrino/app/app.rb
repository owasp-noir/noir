require 'padrino-core'

# The primary app. A bare `get :name do` written directly in the class
# body (no enclosing `controllers` block) is still a valid named route —
# `Padrino::Routing` is mixed into every `Padrino::Application` subclass.
class PadrinoTest < Padrino::Application
  register Padrino::Helpers

  get '/' do
    puts params[:query]
    puts cookies[:session]
  end

  get :status do
    # url_for(:status) => "/status"
    'ok'
  end
end
