# NoirTechs catalog entry: cs_hotchocolate.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  HOTCHOCOLATE = {
    :cs_hotchocolate => {
      :framework => "HotChocolate",
      :language  => "C#",
      :similar   => ["hotchocolate", "hot-chocolate", "hot_chocolate", "cs-hotchocolate", "cs_hotchocolate", "c# hotchocolate", "c#-hotchocolate", "c#_hotchocolate"],
      :supported => {
        :endpoint => true,
        :method   => false,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
        :static_path => false,
        :websocket   => true,
      },
    },
  }
end
