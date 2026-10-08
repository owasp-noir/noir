module Mutations
  class DeletePost < GraphQL::Schema::Mutation
    argument :post_id, ID, required: true

    field :ok, Boolean, null: false
  end
end
