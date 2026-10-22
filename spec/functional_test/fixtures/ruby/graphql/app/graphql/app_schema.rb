class AppSchema < GraphQL::Schema
  query Types::QueryType
  mutation(Types::MutationType)
  subscription Types::SubscriptionType
end
