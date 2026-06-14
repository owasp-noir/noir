module MyAPI
  class Widgets < ::MyAPI::Base
    # resource carrying a trailing `requirements:` kwarg before `do`.
    resource :widgets, requirements: { id: /\d+/ } do
      post do
        present :ok
      end
    end
  end
end
