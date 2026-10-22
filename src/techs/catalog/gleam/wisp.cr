# NoirTechs catalog entry: gleam_wisp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Gleam
  WISP = {
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
