# NoirTechs catalog entry: cs_razor.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Csharp
  RAZOR = {
    :cs_razor => {
      :framework => "ASP.NET Razor Pages / Blazor",
      :language  => "C#",
      :similar   => ["razor", "razor-pages", "razor_pages", "razorpages", "blazor", "cs-razor", "cs_razor", "c#-razor", "c#_razor"],
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
    },
  }
end
