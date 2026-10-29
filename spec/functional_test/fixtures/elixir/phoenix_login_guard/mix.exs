defmodule PhoenixLoginGuard.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_login_guard,
      version: "0.1.0",
      elixir: "~> 1.16",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"}
    ]
  end
end
