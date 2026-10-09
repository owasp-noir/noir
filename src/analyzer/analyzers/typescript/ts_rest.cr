require "../../engines/ts_contract_engine"

module Analyzer::Typescript
  # ts-rest (https://ts-rest.com) contracts:
  #
  #   export const contract = c.router({
  #     getPost: { method: 'GET', path: '/posts/:id', responses: { 200: Post } },
  #   }, { pathPrefix: '/api' });
  #
  # Served through `createExpressEndpoints` / Fastify / Next adapters that
  # never spell the paths out, so the contract is the only place they live.
  class TsRest < TSContractEngine
    analyzer_for "ts_tsrest"

    MARKER = /['"]@ts-rest\/core['"]/

    def candidate?(content : String) : Bool
      content.matches?(MARKER)
    end

    def routes(content : String) : Array(Noir::TSContractExtractor::Route)
      Noir::TSContractExtractor.ts_rest(content)
    end
  end
end
