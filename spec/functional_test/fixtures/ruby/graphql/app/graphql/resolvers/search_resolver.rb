module Resolvers
  class SearchResolver < BaseResolver
    type [Types::PostType], null: false

    argument :term, String, required: true
    argument :max_results, Integer, required: false

    def resolve(term:, max_results: 10)
      Post.search(term).limit(max_results)
    end
  end
end
