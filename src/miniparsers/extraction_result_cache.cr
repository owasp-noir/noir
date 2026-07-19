# Process-wide memo helpers for pure tree-sitter / lexer extractors.
#
# Large monorepo scans re-enter the same extractors many times on the
# same source string:
#   * one analyzer calls decorations + blueprints (two full parses)
#   * concurrent tech analyzers re-parse the same CodeLocator-cached
#     content for sibling frameworks that both survived detection
#
# Trees themselves cannot be cached (lifetime is tied to the parse
# block), but the *derived* route/decoration/constant tables can. Keys
# combine a content fingerprint so GC reuse of `object_id` cannot
# return a stale hit.
module Noir::ExtractionResultCache
  extend self

  # Soft cap per typed store. Beyond this, the oldest half of entries
  # is dropped (FIFO on insertion order). Extraction results are small
  # relative to source text; the cap mainly bounds pathological cases.
  DEFAULT_MAX_ENTRIES = 4096

  # Stable-ish fingerprint for a source buffer. Prefer this over bare
  # `object_id` — the CodeLocator content cache reuses String instances
  # across analyzers (good hit rate), but object_id alone is unsafe if
  # a short-lived string is freed and the id is recycled.
  def source_fingerprint(source : String) : UInt64
    # Crystal's String#hash is content-based; mix in object_id so two
    # identical buffers that are distinct instances still share a key
    # when content matches (hash) while remaining O(1) to compute for
    # the already-interned CodeLocator path (same instance → same id).
    h = source.hash.to_u64!
    h &+= source.bytesize.to_u64! &* 0x9e3779b97f4a7c15_u64
    h
  end

  # Combine source fingerprint with a cheap options tag (e.g. joined
  # router names). Callers should keep the tag deterministic.
  def key(source : String, *options : String) : UInt64
    h = source_fingerprint(source)
    options.each do |opt|
      h &+= opt.hash.to_u64! &* 0xbf58476d1ce4e5b9_u64
    end
    h
  end

  # Insert-or-fetch with a typed Hash store. `store` and `order` are
  # owned by the caller so each extractor keeps its own type-safe map.
  def fetch(store : Hash(UInt64, T), order : Array(UInt64), key : UInt64, mutex : Mutex, & : -> T) : T forall T
    fetch(store, order, key, mutex, DEFAULT_MAX_ENTRIES) { yield }
  end

  def fetch(store : Hash(UInt64, T), order : Array(UInt64), key : UInt64, mutex : Mutex, max_entries : Int32, & : -> T) : T forall T
    mutex.synchronize do
      if hit = store[key]?
        return hit
      end
    end

    value = yield

    mutex.synchronize do
      unless store.has_key?(key)
        if store.size >= max_entries
          # Drop oldest half.
          drop = store.size // 2
          drop = 1 if drop < 1
          drop.times do
            old = order.shift?
            break unless old
            store.delete(old)
          end
        end
        store[key] = value
        order << key
      end
      # Another fiber may have filled the same key first; prefer the
      # stored entry so all callers share one array.
      store[key]
    end
  end

  def clear(store : Hash(UInt64, T), order : Array(UInt64), mutex : Mutex) : Nil forall T
    mutex.synchronize do
      store.clear
      order.clear
    end
  end

  # Registered clear callbacks for typed extractor stores. Invoked at
  # the start of each scan so a long-lived process (diff mode, repeated
  # library use) cannot serve memo entries from a previous codebase.
  @@clearers = [] of -> Nil
  @@clearers_mutex = Mutex.new

  def register_clearer(&block : -> Nil) : Nil
    @@clearers_mutex.synchronize { @@clearers << block }
  end

  def clear_all : Nil
    clearers = @@clearers_mutex.synchronize { @@clearers.dup }
    clearers.each(&.call)
  end
end
