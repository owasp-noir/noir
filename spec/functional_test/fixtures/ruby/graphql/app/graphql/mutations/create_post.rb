class Mutations::CreatePost < Mutations::BaseMutation
  argument :title, String, required: true
  argument :body_text, String, required: false

  field :post, Types::PostType, null: true
end
