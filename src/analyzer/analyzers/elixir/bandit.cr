require "./elixir_plug"

module Analyzer::Elixir
  # Bandit (https://github.com/mtrudel/bandit) is the modern HTTP
  # server that ships with Phoenix 1.7+ and is increasingly used to
  # host raw `Plug.Router` modules. Route registration syntax inside
  # the router is identical to `Plug.Router`, so we reuse the Plug
  # extraction logic and only rename the analyzer so endpoints get
  # tagged with the `elixir_bandit` technology.
  class Bandit < Plug
  end
end
