defmodule App.Schema do
  use Absinthe.Schema

  query do
    field :list_items, list_of(:string) do
      arg :page_size, :integer
    end
  end
end

defmodule App.Router do
  use Plug.Router

  plug :match
  plug :dispatch

  # The Passthrough adapter keeps snake_case names on the wire.
  forward "/gql", to: Absinthe.Plug, init_opts: [schema: App.Schema, adapter: Absinthe.Adapter.Passthrough]
end
