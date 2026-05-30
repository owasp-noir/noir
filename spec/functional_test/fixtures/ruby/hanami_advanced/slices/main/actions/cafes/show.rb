module Main
  module Actions
    module Cafes
      class Show < Main::Action
        def handle(request, response)
          cafe = CafeRepo.find(request.params[:id])
          response.render cafe
        end
      end
    end
  end
end
