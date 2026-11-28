Billing::Engine.routes.draw do
  resources :locations
  get "status", to: "status#show"
  get "ping", to: proc { [200, {}, ["ok"]] }
  get "old", to: redirect("/locations")
  mount ExportApp, at: "/export"
end
