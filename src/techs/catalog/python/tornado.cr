# NoirTechs catalog entry: python_tornado.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Python
  TORNADO = {
    :python_tornado => {
      :framework => "Tornado",
      :language  => "Python",
      :similar   => ["tornado", "python-tornado", "python_tornado"],
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
      :context => {:callee => true, :guards => true},
    },
  }
end
