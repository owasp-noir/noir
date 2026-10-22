defmodule TestSupport.FixtureSchema do
  use Absinthe.Schema

  query do
    field :should_not_appear_test_fixture, :string do
      resolve(fn _, _, _ -> {:ok, "x"} end)
    end
  end
end
