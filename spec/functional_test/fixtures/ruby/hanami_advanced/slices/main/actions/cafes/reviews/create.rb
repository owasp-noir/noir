module Main
  module Actions
    module Cafes
      module Reviews
        class Create < Main::Action
          params do
            required(:content).filled(:string)
            required(:rating).filled(:integer)
          end

          def handle(request, response)
            result = CreateReview.call(request.params.to_h)
            response.render result
          end
        end
      end
    end
  end
end
