class ApplicationController < ActionController::Base
  private

  def params_for(key)
    params.require(key)
  end
end
