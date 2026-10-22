defmodule App.MixProject do
  use Mix.Project
  def project, do: [app: :app, deps: deps()]
  defp deps, do: [{:phoenix, "~> 1.7.0"}]
end
