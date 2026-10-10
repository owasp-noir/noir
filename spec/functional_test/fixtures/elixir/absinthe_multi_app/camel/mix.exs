defmodule Camel.MixProject do
  use Mix.Project

  def project do
    [app: :camel, version: "0.1.0", deps: [{:absinthe, "~> 1.7"}]]
  end
end
