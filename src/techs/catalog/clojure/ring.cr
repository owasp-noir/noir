# NoirTechs catalog entry: clojure_ring.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Clojure
  RING = {
    :clojure_ring => {
      :framework => "Ring",
      :language  => "Clojure",
      :similar   => ["ring", "clojure-ring", "clojure_ring", "clj-ring"],
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
    },
  }
end
