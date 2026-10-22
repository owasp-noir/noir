# Case folding for the extensions of stacks written on case-insensitive
# Windows/IIS filesystems, where `LOGIN.ASP`, `P.ASPX` and `A.PHP` are the
# same pages as their lower-case spellings and routinely show up that way
# in checkouts.
#
# Deliberately a closed list, not every extension: elsewhere case is
# meaningful — `.C`/`.H` are C++ next to C's `.c`/`.h`, `Makefile.PL` is a
# Perl build script rather than a `.pl` source, and `.R` already has its
# own spelling in the R analyzer.
module Noir::FileExtension
  CASE_INSENSITIVE = Set{
    ".asp", ".asa", ".aspx", ".asmx", ".ashx", ".ascx", ".master", ".svc",
    ".cs", ".csproj", ".cshtml", ".razor", ".vb", ".vbproj", ".vbhtml",
    ".cfm", ".cfc", ".cfml", ".php",
  }

  # `path` with its extension lower-cased when that extension is a
  # `CASE_INSENSITIVE` one spelled with upper-case letters; otherwise
  # `path` itself, without allocating.
  def self.fold(path : String) : String
    i = path.bytesize - 1
    upper = false
    while i >= 0
      char = path.to_unsafe[i].unsafe_chr
      break if char == '.' || char == '/' || char == '\\'
      upper ||= char.ascii_uppercase?
      i -= 1
    end
    return path unless upper && i > 0 && path.to_unsafe[i] == '.'.ord
    extension = path.byte_slice(i).downcase
    CASE_INSENSITIVE.includes?(extension) ? path.byte_slice(0, i) + extension : path
  end

  # The key `File.extname` results are indexed and looked up under.
  def self.index_key(extension : String) : String
    folded = extension.downcase
    CASE_INSENSITIVE.includes?(folded) ? folded : extension
  end
end
