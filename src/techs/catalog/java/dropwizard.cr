# NoirTechs catalog entry: java_dropwizard.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Java
  DROPWIZARD = {
    :java_dropwizard => {
      :framework => "Dropwizard",
      :language  => "Java",
      :similar   => ["dropwizard", "java-dropwizard", "java_dropwizard"],
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
