Rails.application.routes.draw do
  mount ActionCable.server => "/cable"
end
