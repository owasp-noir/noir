Rails.application.routes.draw do
  get '/from_lib_routes', to: 'home#index'
end
