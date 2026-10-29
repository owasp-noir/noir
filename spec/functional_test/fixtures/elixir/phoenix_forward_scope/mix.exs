defmodule ForwardScope.MixProject do
  use Mix.Project

  def project do
    [app: :forward_scope, version: "0.1.0", deps: deps()]
  end

  defp deps do
    [{:phoenix, "~> 1.7.1"}]
  end
end
