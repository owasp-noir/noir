# NoirTechs catalog entry: java_vaadin.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  VAADIN = {
    :java_vaadin => {
      :framework => "Vaadin",
      :language  => "Java",
      :similar   => ["vaadin", "vaadin-flow", "hilla", "java-vaadin", "java_vaadin"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
    },
  }
end
