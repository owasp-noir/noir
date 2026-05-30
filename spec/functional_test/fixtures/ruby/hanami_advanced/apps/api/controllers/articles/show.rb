module Api
  module Controllers
    module Articles
      class Show
        include Api::Action

        def call(params)
          ArticleRepository.find_by_slug(params.get(:slug))
        end
      end
    end
  end
end
