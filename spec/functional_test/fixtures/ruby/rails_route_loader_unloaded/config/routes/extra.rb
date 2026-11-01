Rails.application.routes.draw do
  get '/from_config_routes', to: 'home#index'
end
