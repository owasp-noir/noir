# NoirTechs catalog: gleam technologies.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  GLEAM = {
    :gleam_wisp => {
      :framework => "Wisp",
      :language  => "Gleam",
      :similar   => ["wisp", "gleam-wisp", "gleam_wisp"],
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
        :websocket   => false,
      },
    },
  }
end
