defmodule Hello.MiniRouter do
  # An in-app DSL whose macro shares a name with the Phoenix verb. The
  # router never imports it, so `get "/"` there is still Phoenix's `get`.
  defmacro get(path, do: block) do
    quote do
      match_route(:get, unquote(path), unquote(block))
    end
  end
end
