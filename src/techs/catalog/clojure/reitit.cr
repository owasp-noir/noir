# NoirTechs catalog entry: clojure_reitit.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Clojure
  REITIT = {
    :clojure_reitit => {
      :framework => "Reitit",
      :language  => "Clojure",
      :similar   => ["reitit", "clojure-reitit", "clojure_reitit", "clj-reitit", "metosin-reitit"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
