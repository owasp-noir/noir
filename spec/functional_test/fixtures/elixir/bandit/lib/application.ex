defmodule ElixirBandit.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Bandit, plug: ElixirBandit.Router, port: 4000}
    ]

    opts = [strategy: :one_for_one, name: ElixirBandit.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
