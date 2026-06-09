defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app_a,
      version: "0.1.0",
      deps: deps()
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"}
    ]
  end
end
