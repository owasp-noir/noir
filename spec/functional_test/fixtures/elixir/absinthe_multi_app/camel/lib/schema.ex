defmodule Camel.Schema do
  use Absinthe.Schema

  query do
    field :all_users, list_of(:string)
  end
end
