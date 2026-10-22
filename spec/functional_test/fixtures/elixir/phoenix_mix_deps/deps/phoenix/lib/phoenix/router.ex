defmodule Phoenix.Router do
  @moduledoc """
  Defines a Phoenix router.

  The router provides a set of macros for generating routes
  that dispatch to specific controllers and actions. Those
  macros are named after HTTP verbs. For example:

      defmodule MyAppWeb.Router do
        use Phoenix.Router

        get "/pages/:page", PageController, :show
      end
  """
end
