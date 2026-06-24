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
  # Entry tuple shape, attaching collected callees to an endpoint, and
  # de-duplicating them — lives here so a change to the Callee contract lands
  # once instead of being copy-pasted across every extractor.
  module CalleeExtractorBase
    # A discovered callee: (name, file path, 1-based line number).
    alias Entry = Tuple(String, String, Int32)

    # Attach collected callees to an endpoint as Callee records.
    def attach_to(endpoint : Endpoint, callees : Array(Entry))
      callees.each do |name, path, line|
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end
    end

    # Drop duplicate (name, path, line) entries, preserving first-seen order.
    # Entry is a value tuple, so set membership compares by value; this is
    # equivalent to the former per-extractor string-key and Array#uniq forms.
    private def dedup_entries(entries : Array(Entry)) : Array(Entry)
      seen = Set(Entry).new
      entries.select { |entry| seen.add?(entry) }
    end
  end
end
