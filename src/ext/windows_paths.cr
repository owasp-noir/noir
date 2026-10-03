# noir handles every path as a `/`-separated string: the walk, the
# analyzers' scope and convention checks, the import graph and the reported
# `code_path` all match on `/`. On Windows the stdlib builds paths with `\`
# instead, so a path from `File.join` and the same path from the walk
# compared unequal and whole projects reported nothing.
#
# Rather than route ~800 `File.join` / `File.expand_path` call sites through
# a helper, the path-producing stdlib methods return `/` on Windows. Every
# Windows file API accepts `/`, and `\` can't appear in a Windows file name,
# so the swap is lossless. Compiled out everywhere else.
{% if flag?(:windows) %}
  class File
    def self.join(*parts : String | Path) : String
      previous_def.gsub('\\', '/')
    end

    def self.join(parts : Enumerable) : String
      previous_def.gsub('\\', '/')
    end

    def self.expand_path(path : Path | String, dir = nil, *, home = false) : String
      previous_def.gsub('\\', '/')
    end

    def self.realpath(path : Path | String) : String
      previous_def.gsub('\\', '/')
    end
  end

  class Dir
    def self.current : String
      previous_def.gsub('\\', '/')
    end

    def self.tempdir : String
      previous_def.gsub('\\', '/')
    end
  end
{% end %}
