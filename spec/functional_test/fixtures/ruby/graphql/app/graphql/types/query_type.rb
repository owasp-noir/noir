module Types
  class QueryType < Types::BaseObject
    include GraphQL::Types::Relay::HasNodeField
    include Types::UserQueries

    field :post, PostType, null: true do
      argument :id, ID, required: true
    end

    field :posts, [PostType], null: false,
      description: "All posts" do
      argument :author_id, ID, required: false
      argument :order_by, String, required: false, camelize: false
    end

    field :posts_connection, PostType.connection_type, null: false
    field :viewer_name, String, camelize: false
    field :search, resolver: Resolvers::SearchResolver

    def post(id:)
      Post.find(id)
    end
  end
end
