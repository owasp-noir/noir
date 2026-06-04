module Main
  module Actions
    module Widgets
      class Build < Main::Action
        params do
          required(:quantity).filled(:integer)
        end

        def handle(request, response)
          response.render(request.params[:id])
        end
      end
    end
  end
end
