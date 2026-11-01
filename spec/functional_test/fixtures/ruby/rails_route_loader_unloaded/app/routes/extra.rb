Rails.application.routes.draw do
  get '/from_app_routes', to: 'home#index'
end
