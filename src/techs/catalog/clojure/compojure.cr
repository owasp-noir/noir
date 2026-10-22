# NoirTechs catalog entry: clojure_compojure.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Clojure
  COMPOJURE = {
    :clojure_compojure => {
      :framework => "Compojure",
      :language  => "Clojure",
      :similar   => ["compojure", "clojure-compojure", "clojure_compojure", "clj-compojure"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
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
