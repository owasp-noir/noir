# NoirTechs catalog entry: clojure_cli.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Clojure
  CLI = {
    :clojure_cli => {
      :framework => "CLI (clojure.tools.cli / cli-matic / environ / babashka.cli)",
      :language  => "Clojure",
      :similar   => ["clojure-cli", "clojure_cli", "tools.cli", "cli-matic", "environ", "babashka-cli", "babashka.cli"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
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
