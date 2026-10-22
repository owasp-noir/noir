require "../../../models/detector"

module Detector::CSharp
  class Abp < Detector
    detector_for "cs_abp", extensions: %w[.cs .csproj]

    SERVICE_BASE_RE = /:\s*(?:Volo\.Abp\.Application\.Services\.)?(?:ApplicationService|(?:Crud|ReadOnly)AppService\s*<)/

    # ABP Framework: a `Volo.Abp.*` package reference, the
    # `ConventionalControllers.Create(...)` registration, or an application
    # service deriving from ABP's bases in a file that imports `Volo.Abp`.
    def detect(filename : String, file_contents : String) : Bool
      name = Noir::FileExtension.fold(filename)
      return file_contents.includes?("Include=\"Volo.Abp.") if name.ends_with?(".csproj")
      return false unless name.ends_with?(".cs")
      return true if file_contents.includes?("ConventionalControllers.Create")
      file_contents.includes?("Volo.Abp") && file_contents.matches?(SERVICE_BASE_RE)
    end
  end
end
