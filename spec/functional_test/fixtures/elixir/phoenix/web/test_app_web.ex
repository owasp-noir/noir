defmodule TestApp.Web do
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end

  def controller do
    quote do
      use Phoenix.Controller
      # If your actual project has a view, import it, e.g.:
      # import TestApp.Web.Router.Helpers
      # alias TestApp.Web.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
    end
  end
end
