require "../models/endpoint"

module Noir
  # Shared skeleton for the per-language callee extractors. Each extractor is
  #
  #     module Noir::FooCalleeExtractor
  #       extend self
  #       include Noir::CalleeExtractorBase
  #       # ...language-specific scan_line / skip_callee? / regex tables...
  #     end
  #
  # and supplies only the language-specific scanning. The generic glue — the
  # Entry tuple shape and attaching collected callees to an endpoint — lives
  # here so a change to the Callee contract lands once instead of being
  # copy-pasted across every extractor.
  module CalleeExtractorBase
    # A discovered callee: (name, file path, 1-based line number).
    alias Entry = Tuple(String, String, Int32)

    # Attach collected callees to an endpoint as Callee records.
    def attach_to(endpoint : Endpoint, callees : Array(Entry))
      callees.each do |name, path, line|
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end
    end
  end
end
