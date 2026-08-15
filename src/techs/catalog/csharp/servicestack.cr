# NoirTechs catalog entry: cs_servicestack.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  SERVICESTACK = {
    :cs_servicestack => {
      :framework => "ServiceStack",
      :language  => "C#",
      :similar   => ["servicestack", "service-stack", "cs-servicestack", "cs_servicestack", "c# servicestack", "c#-servicestack", "c#_servicestack"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
