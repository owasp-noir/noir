module Types
  class SubscriptionType < GraphQL::Schema::Object
    graphql_name "RootSubscription"

    field :post_added, Types::PostType, null: false, description: "A post was added" do
      argument :room_id, ID
    end
  end
end
