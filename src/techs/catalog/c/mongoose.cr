# NoirTechs catalog entry: c_mongoose.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::C
  MONGOOSE = {
    :c_mongoose => {
      :framework => "Mongoose",
      :language  => "C",
      :similar   => ["mongoose", "cesanta-mongoose", "c-mongoose", "c_mongoose", "mongoose.ws"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
      :context => {:callee => true},
    },
  }
end
