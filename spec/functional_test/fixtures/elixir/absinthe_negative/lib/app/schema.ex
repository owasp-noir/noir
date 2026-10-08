# Not an Absinthe schema: the same `query do` / `field` shapes from another
# DSL must yield nothing.
defmodule App.Schema do
  use App.Dsl

  query do
    field :posts, list_of(:post) do
      arg :id, :id
    end
  end
end
