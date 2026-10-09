require "../../engines/ts_contract_engine"

module Analyzer::Typescript
  # oRPC (https://orpc.unnoq.com) procedures and contracts with an OpenAPI
  # route:
  #
  #   export const getPlanet = os
  #     .route({ method: 'GET', path: '/planets/{id}' })
  #     .input(z.object({ id: z.number() }))
  #     .handler(...)
  #
  # `method` defaults to POST. Procedures without `.route()` are RPC-only
  # and are not reported.
  class Orpc < TSContractEngine
    analyzer_for "ts_orpc"

    MARKER = /['"]@orpc\/(?:server|contract)['"]/

    def marker : Regex
      MARKER
    end

    def routes(content : String) : Array(Noir::TSContractExtractor::Route)
      Noir::TSContractExtractor.orpc(content)
    end
  end
end
