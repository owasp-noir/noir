module Twitter
  class HeaderAPI < Grape::API
    version 'v2', using: :header, vendor: 'twitter'

    get :header_versioned do
      'x'
    end
  end
end
