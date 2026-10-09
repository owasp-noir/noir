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

    MARKER = /['"](?:@effect\/platform|effect\/unstable\/httpapi)['"]/

    def marker : Regex
      MARKER
    end

    def routes(content : String) : Array(Noir::TSContractExtractor::Route)
      return [] of Noir::TSContractExtractor::Route unless content.includes?("HttpApiEndpoint")
      Noir::TSContractExtractor.effect(content)
    end
  end
end
