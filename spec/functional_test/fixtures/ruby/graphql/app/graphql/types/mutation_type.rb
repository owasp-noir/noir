module Types
  class MutationType < Types::BaseObject
    field :create_post, mutation: Mutations::CreatePost
    field :delete_post, mutation: Mutations::DeletePost
  end
end
