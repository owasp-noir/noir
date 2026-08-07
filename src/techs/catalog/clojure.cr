# NoirTechs catalog: clojure technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  CLOJURE = {
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
    },
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
    },
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
    },
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
