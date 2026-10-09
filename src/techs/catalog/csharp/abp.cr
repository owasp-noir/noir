# NoirTechs catalog entry: cs_abp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  ABP = {
    :cs_abp => {
      :framework => "ABP Framework",
      :language  => "C#",
      :similar   => ["abp", "abp-framework", "abp framework", "cs-abp", "cs_abp", "c# abp", "c#-abp", "c#_abp", "volo.abp"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => false,
      },
      :context => {:callee => true},
    },
  }
end
