# NoirTechs catalog: crystal technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  CRYSTAL = {
    :crystal_cli => {
      :framework => "CLI (OptionParser / clim / admiral / commander.cr)",
      :language  => "Crystal",
      :similar   => ["crystal-cli", "crystal_cli", "optionparser", "clim", "admiral"],
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
    :crystal_amber => {
      :framework => "Amber",
      :language  => "Crystal",
      :similar   => ["amber", "crystal-amber", "crystal_amber"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => true,
      },
    },
    :crystal_kemal => {
      :framework => "Kemal",
      :language  => "Crystal",
      :similar   => ["kemal", "crystal-kemal", "crystal_kemal"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :crystal_lucky => {
      :framework => "Lucky",
      :language  => "Crystal",
      :similar   => ["lucky", "crystal-lucky", "crystal_lucky"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :crystal_marten => {
      :framework => "Marten",
      :language  => "Crystal",
      :similar   => ["marten", "crystal-marten", "crystal_marten"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => true,
        :websocket   => false,
      },
    },
    :crystal_grip => {
      :framework => "Grip",
      :language  => "Crystal",
      :similar   => ["grip", "crystal-grip", "crystal_grip"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
    :crystal_http => {
      :framework => "HTTP::Server",
      :language  => "Crystal",
      :similar   => ["http", "http_server", "crystal-http", "crystal_http", "http/server", "std/http"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
