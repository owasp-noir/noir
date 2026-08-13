# NoirTechs catalog entry: supabase.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
module NoirTechs::Catalog::Specification
  SUPABASE = {
    :supabase => {
      :format    => ["SQL"],
      :similar   => ["supabase", "postgrest", "supabase-migrations", "supabase_migrations", "pgrst"],
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
      },
    },
  }
end
