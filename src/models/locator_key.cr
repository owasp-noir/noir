module Noir
  # A declared slot in `CodeLocator`.
  #
  # `T` is the stored shape: `String` for single-value slots (`set`/`get`),
  # `Array(String)` for append-only ones (`push`/`all`). `CodeLocator` takes
  # `LocatorKey(T)` and never a bare `String`, so the compiler is the
  # registry check — a literal key nobody declared does not build, and
  # `push`ing to a single-value slot (or `get`ting an append-only one) is a
  # type error rather than a silently-empty read.
  #
  # Before this, the locator was a blackboard of 63 magic strings: a detector
  # wrote one, an analyzer read it, and nothing connected the two. The only
  # way to learn that `grpc-proto` has two independent reader families was to
  # grep for the string.
  struct LocatorKey(T)
    enum Lifecycle
      # Written by the detector pass for the analyzers to drain. Cleared at
      # the top of `detect_techs`, before the first file is walked.
      DetectScoped

      # Written and read within one analysis pass. Cleared at the top of
      # `analysis_endpoints`.
      AnalyzeScoped

      # Never cleared automatically; only `CodeLocator#clear_all` drops it.
      # For slots a library caller owns the lifetime of.
      Process
    end

    getter name : String
    getter lifecycle : Lifecycle

    # Subsystem that writes the slot, as a source-path fragment. Read by the
    # integrity spec, and by whoever next has to work out why a key exists.
    getter owner : String

    def initialize(@name : String, @lifecycle : Lifecycle, @owner : String)
    end
  end

  # A family of keys minted at runtime under one declared prefix
  # (`<prefix>:<file>` / `<prefix>:<file>:<function>`). Declared once; the
  # minted keys inherit its lifecycle and are cleared by prefix.
  #
  # Exists for the Express router-prefix keys, which are the one family whose
  # names are not knowable ahead of time — and which, under a
  # string-constants design, would have stayed invisible to any enforcement.
  struct LocatorKeyNamespace
    getter prefix : String
    getter lifecycle : LocatorKey::Lifecycle
    getter owner : String

    def initialize(@prefix : String, @lifecycle : LocatorKey::Lifecycle, @owner : String)
    end

    def key(*parts : String) : LocatorKey(Array(String))
      name = String.build do |io|
        io << @prefix
        parts.each { |part| io << ':' << part }
      end
      LocatorKey(Array(String)).new(name, @lifecycle, @owner)
    end

    def matches?(name : String) : Bool
      name.starts_with?("#{@prefix}:")
    end
  end
end
