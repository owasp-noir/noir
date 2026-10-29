# NoirTechs catalog entry: js_medusa.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Javascript
  MEDUSA = {
    :js_medusa => {
      :framework => "Medusa",
      :language  => "JavaScript",
      :similar   => ["medusa", "medusajs", "js-medusa", "js_medusa", "@medusajs/medusa"],
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
      :context => {:guards => true},
    },
  }
end
