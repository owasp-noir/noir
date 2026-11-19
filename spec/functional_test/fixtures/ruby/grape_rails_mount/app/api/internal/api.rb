module Internal
  class API < Grape::API
    get :status do
      { ok: true }
    end
  end
end
