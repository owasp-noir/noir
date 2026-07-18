require "../../../models/detector"

module Detector::Aspnet
  class WebForms < Detector
    # `<%@ Page %>` / `<%@ Control %>` / `<%@ WebHandler %>` /
    # `<%@ WebService %>` directives, and the `runat="server"` marker that
    # every WebForms control carries. Directives routinely span several
    # physical lines, so the language attribute is not anchored to line 1.
    DIRECTIVE_RE = /<%@\s*(?:Page|Control|Master|WebHandler|WebService|Application)\b/i
    RUNAT_RE     = /\brunat\s*=\s*["']?server["']?/i

    # Code-behind: a partial class deriving from the WebForms page/control
    # base types, in either C# or VB.
    CODEBEHIND_RE = /(?::|Inherits\s+)\s*(?:System\.Web\.UI\.)?(?:Page|UserControl|MasterPage)\b|\bSystem\.Web\.UI\b/i

    MARKUP_EXTENSIONS = {".aspx", ".ascx", ".ashx", ".asmx", ".master"}

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      if MARKUP_EXTENSIONS.includes?(File.extname(filename).downcase)
        return true if file_contents.matches?(DIRECTIVE_RE)
        return true if file_contents.matches?(RUNAT_RE)
        return false
      end

      # `.cs` / `.vb` only count as WebForms when they are page code-behind;
      # otherwise every ASP.NET Core project would match.
      file_contents.matches?(CODEBEHIND_RE)
    end

    def applicable?(filename : String) : Bool
      extension = File.extname(filename).downcase
      return true if MARKUP_EXTENSIONS.includes?(extension)

      # Only code-behind siblings, never arbitrary sources.
      filename.downcase.matches?(/\.(?:aspx|ascx|ashx|asmx|master)\.(?:cs|vb)\z/)
    end

    def set_name
      @name = "aspnet_webforms"
    end
  end
end
