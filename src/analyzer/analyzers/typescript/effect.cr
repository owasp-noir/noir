require "../../engines/ts_contract_engine"

module Analyzer::Typescript
  # Effect HttpApi (`@effect/platform`, `effect/unstable/httpapi`):
  #
  #   HttpApiGroup.make("users")
  #     .add(HttpApiEndpoint.get("findById", "/users/:id"))
  #     .add(HttpApiEndpoint.del("remove")`/users/${idParam}`)
  #     .prefix("/v1")
  #
  # `setPayload` / `setUrlParams` / `setHeaders` schemas become params.
  class Effect < TSContractEngine
    analyzer_for "ts_effect"

    # The module name is the marker; it is imported from the package root,
    # a subpath (`@effect/platform/HttpApiEndpoint`) or a local re-export.
    def candidate?(content : String) : Bool
      content.includes?("HttpApiEndpoint")
    end

    def routes(content : String) : Array(Noir::TSContractExtractor::Route)
      Noir::TSContractExtractor.effect(content)
    end
  end
end
