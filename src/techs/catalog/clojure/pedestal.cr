# NoirTechs catalog entry: clojure_pedestal.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Clojure
  PEDESTAL = {
    :clojure_pedestal => {
      :framework => "Pedestal",
      :language  => "Clojure",
      :similar   => ["pedestal", "clojure-pedestal", "clojure_pedestal", "clj-pedestal", "io-pedestal"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => false,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
