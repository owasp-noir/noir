Ledger::Component.routes.draw do
  resources :entries, only: [:index, :show]
end
