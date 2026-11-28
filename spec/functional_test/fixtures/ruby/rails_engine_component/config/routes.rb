Rails.application.routes.draw do
  mount Billing::Engine, at: "/billing"
  mount Ledger::Component, at: "/ledger"
  mount Reports::Component, at: "/reports"
end
