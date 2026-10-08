defmodule BlogWeb.Schema.AccountTypes do
  use Absinthe.Schema.Notation

  object :user do
    field :id, :id
    field :name, :string
  end

  object :account_queries do
    field :me, :user

    field :search_users, list_of(:user) do
      arg :name_prefix, non_null(:string)
      arg :filter, :user_filter_input
    end

    import_fields :admin_queries
  end

  object :admin_queries do
    field :all_users, non_null(list_of(non_null(:user)))
  end

  input_object :user_filter_input do
    field :active, :boolean
  end

  extend object(:mutation) do
    field :update_profile, :user do
      arg :display_name, :string
    end
  end
end
