defmodule App.MixProject do
  use Mix.Project

  def project do
    [app: :app, version: "0.1.0", deps: [{:absinthe, "~> 1.7"}, {:absinthe_plug, "~> 1.5"}]]
  end
end
