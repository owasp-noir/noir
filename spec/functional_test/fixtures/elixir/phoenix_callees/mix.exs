defmodule ElixirPhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_phoenix_callees,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.1"}
    ]
  end
end
