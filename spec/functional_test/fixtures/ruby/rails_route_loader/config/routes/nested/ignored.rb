# Not matched by `routes/*.rb`, so Rails never loads it.
Sample::Application.routes.draw do
  get '/nested_only', to: 'tickets#index'
end
