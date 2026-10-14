defmodule Hello.MixProject do
  use Mix.Project

  def project do
    [app: :hello, version: "0.1.0", elixir: "~> 1.15", deps: deps()]
  end

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:bandit, "~> 1.5"}
    ]
  end
end
