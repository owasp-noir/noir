Rails.application.routes.draw do
  get "/reports", to: "reports#index"
  get "/reports/ordered", to: "reports#ordered"
  post "/reports/notify", to: "reports#notify"
  post "/reports/convert", to: "reports#convert"
  get "/reports/safe", to: "reports#safe"
end
