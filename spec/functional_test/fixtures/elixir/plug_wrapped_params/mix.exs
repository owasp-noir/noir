defmodule ElixirPlug.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_plug,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirPlug.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.14"},
      {:plug_cowboy, "~> 2.5"}
    ]
  end
end