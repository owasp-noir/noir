defmodule ElixirPhoenixAuth.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_phoenix_auth,
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
