module Main
  module Actions
    module Cafes
      module Reviews
        class New < Main::Action
          def handle(request, response)
            response.render ReviewForm.build(request.params[:cafe_id])
          end
        end
      end
    end
  end
end
