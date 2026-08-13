# NoirTechs catalog entry: python_falcon.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  FALCON = {
    :python_falcon => {
      :framework => "Falcon",
      :language  => "Python",
      :similar   => ["falcon", "falconframework", "python-falcon", "python_falcon"],
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
      :context => {:callee => true},
    },
  }
end
