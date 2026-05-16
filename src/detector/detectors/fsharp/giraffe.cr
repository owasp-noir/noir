require "../../../models/detector"

module Detector::Fsharp
  class Giraffe < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      # `paket.dependencies` listing the Giraffe NuGet package.
      if base == "paket.dependencies" && file_contents.match(/^\s*nuget\s+Giraffe(?:\s|$)/m)
        return true
      end

      # MSBuild project files (.fsproj/.csproj — Giraffe can be referenced
      # from a hybrid solution) referencing the Giraffe package.
      if (filename.ends_with?(".fsproj") || filename.ends_with?(".csproj")) &&
         file_contents.match(/<PackageReference\s+Include="Giraffe"/)
        return true
      end

      return false unless filename.ends_with?(".fs") || filename.ends_with?(".fsx")

      return true if file_contents.match(/^\s*open\s+Giraffe(\.|\s|$)/m)
      return true if file_contents.includes?("HttpHandler") &&
                     file_contents.match(/\b(?:route|routef|routeCi|subRoute|subRouteCi|subRoutef|choose)\s+/)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".fs") || filename.ends_with?(".fsx") || filename.ends_with?(".fsproj") || filename.ends_with?(".csproj") || File.basename(filename) == "paket.dependencies"
    end

    def set_name
      @name = "fs_giraffe"
    end
  end
end
