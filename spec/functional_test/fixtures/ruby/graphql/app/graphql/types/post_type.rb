class Types::PostType < Types::BaseObject
  field :id, ID, null: false
  field :title_text, String, null: true do
    argument :truncate, Integer, required: false
  end
end
