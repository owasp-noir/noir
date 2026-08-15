# NoirTechs catalog entries: java_helidon_se, java_helidon_mp.
# One file per technology; `NoirTechs::TECHS` in src/techs/techs.cr is
# macro-derived from every constant under `NoirTechs::Catalog`.
#
# Helidon ships two unrelated routing models under one project, so it
# gets two techs rather than one — same precedent as
# `csharp_aspnet_mvc` / `csharp_aspnet_core_mvc`:
#
#   * SE  — the functional `HttpRouting`/`HttpService` builder DSL,
#     walked by a dedicated tree-sitter analyzer
#     (`Analyzer::Java::HelidonSe`). Query/header/cookie/body params
#     are scanned from the handler body; path params come from the
#     shared `{name}` optimizer pass.
#   * MP  — MicroProfile: plain JAX-RS resource classes. There is no
#     Helidon-specific routing shape here, so `Analyzer::Java::HelidonMp`
#     just drives the shared JAX-RS extractor (same relationship
#     Quarkus has to JAX-RS) — the fuller JAX-RS param surface
#     (matrix/form/etc.) applies.
module NoirTechs::Catalog::Java
  HELIDON_SE = {
    :java_helidon_se => {
      :framework => "Helidon SE",
      :language  => "Java",
      :similar   => ["helidon", "helidon-se", "helidon_se", "java-helidon-se", "java_helidon_se"],
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

  HELIDON_MP = {
    :java_helidon_mp => {
      :framework => "Helidon MP",
      :language  => "Java",
      :similar   => ["helidon-mp", "helidon_mp", "java-helidon-mp", "java_helidon_mp"],
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
