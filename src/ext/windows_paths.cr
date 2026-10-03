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
module Noir::WindowsPaths
  # `\` to `/`, except for an extended-length path (`\\?\C:\...`): Windows
  # passes those to the filesystem verbatim, so `/` there is not a separator.
  def self.to_slash(path : String) : String
    path.starts_with?("\\\\?\\") ? path : path.gsub('\\', '/')
  end
end

{% if flag?(:windows) %}
  class File
    def self.join(*parts : String | Path) : String
      Noir::WindowsPaths.to_slash(previous_def)
    end

    def self.join(parts : Enumerable) : String
      Noir::WindowsPaths.to_slash(previous_def)
    end

    def self.expand_path(path : Path | String, dir = nil, *, home = false) : String
      Noir::WindowsPaths.to_slash(previous_def)
    end

    def self.realpath(path : Path | String) : String
      Noir::WindowsPaths.to_slash(previous_def)
    end

    # On Windows this resolves the path through `GetFullPathNameW`, which
    # rejects an empty string, so `File.exists?("")` raised instead of
    # returning false — and took a whole analyzer down with it (classic
    # ASP.NET MVC checks an optional, often-empty RouteConfig path).
    def self.exists?(path : Path | String) : Bool
      return false if path.to_s.empty?
      previous_def
    end
  end

  class Dir
    def self.current : String
      Noir::WindowsPaths.to_slash(previous_def)
    end

    def self.tempdir : String
      Noir::WindowsPaths.to_slash(previous_def)
    end
  end
{% end %}
