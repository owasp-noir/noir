defmodule App.MixProject do
  use Mix.Project

  def project do
    [app: :app, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [{:phoenix, "~> 1.7"}, {:open_api_spex, "~> 3.18"}]
  end
end
