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
  lib LibC
    fun GetFinalPathNameByHandleW(hFile : HANDLE, lpszFilePath : LPWSTR, cchFilePath : DWORD, dwFlags : DWORD) : DWORD
  end

  module Noir::WindowsPaths
    # The path the OS itself resolves `path` to — every symlink and junction
    # along it followed, short names expanded — the way Python's and Go's
    # Windows `realpath` work. Raises `File::Error` when it does not exist.
    def self.final_path(path : String) : String
      handle = LibC.CreateFileW(Crystal::System.to_wstr(path), LibC::FILE_READ_ATTRIBUTES,
        LibC::DEFAULT_SHARE_MODE, nil, LibC::OPEN_EXISTING, LibC::FILE_FLAG_BACKUP_SEMANTICS,
        LibC::HANDLE.null)
      if handle == LibC::INVALID_HANDLE_VALUE
        raise ::File::Error.from_winerror("Error resolving real path", file: path)
      end

      final = begin
        Crystal::System.retry_wstr_buffer do |buffer, small_buf|
          len = LibC.GetFinalPathNameByHandleW(handle, buffer, buffer.size, 0)
          if 0 < len < buffer.size
            break String.from_utf16(buffer[0, len])
          elsif small_buf && len > 0
            next len
          else
            raise ::File::Error.from_winerror("Error resolving real path", file: path)
          end
        end
      ensure
        LibC.CloseHandle(handle)
      end

      # The API answers in extended-length form; hand back the ordinary one.
      if final.starts_with?("\\\\?\\UNC\\")
        "\\\\#{final[8..]}"
      elsif final.starts_with?("\\\\?\\")
        final[4..]
      else
        final
      end
    end
  end

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

    # Not `previous_def`: the stdlib's Windows `realpath` runs the path
    # through `GetFullPathNameW` and resolves a link only in the *last*
    # component. A path through a symlinked directory (`repo/vendor/id_rsa`
    # with `vendor -> /elsewhere`) came back unresolved, so every
    # "is the real path still under the base?" check passed it — the AI
    # agent's file sandbox among them. It also kept 8.3 short names
    # (`RUNNER~1`) while git and other tools report the long one.
    def self.realpath(path : Path | String) : String
      Noir::WindowsPaths.to_slash(Noir::WindowsPaths.final_path(path.to_s))
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
