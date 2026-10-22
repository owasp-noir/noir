defmodule BlogWeb.Schema do
  use Absinthe.Schema

  import_types Absinthe.Type.Custom
  import_types BlogWeb.Schema.AccountTypes
  import_types BlogWeb.Schema.ContentTypes

  alias BlogWeb.Resolvers

  query do
    @desc "Get all posts"
    field :posts, list_of(:post) do
      arg :author_id, :id
      resolve &Resolvers.Content.list_posts/3
    end

    # field :commented_out, :post
    field(:user, :user) do
      arg(:id, non_null(:id))
      resolve(fn _, %{id: id}, _ -> Resolvers.Accounts.find_user(id) end)
    end

    import_fields :account_queries
  end

  mutation name: "BlogMutations" do
    field :create_post, type: :post do
      arg :title, non_null(:string)
      arg :published_at, :naive_datetime
      arg :tags, list_of(non_null(:string)), default_value: []

      resolve &Resolvers.Content.create_post/3
    end

    field :delete_post, :post, name: "remove_post" do
      arg :id, non_null(:id)
      resolve fn _, _, _ ->
        {:ok, nil}
      end
    end
  end

  subscription do
    field :new_post, :post do
      config fn _args, _info ->
        {:ok, topic: "*"}
      end
    end
  end
end
