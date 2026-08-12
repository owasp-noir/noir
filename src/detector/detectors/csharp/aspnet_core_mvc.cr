require "../../../models/detector"

module Detector::CSharp
  class AspNetCoreMvc < Detector
    detector_for "cs_aspnet_core_mvc",
      extensions: %w[.cs .csproj .vbproj .sln .config]

    def detect(filename : String, file_contents : String) : Bool
      is_csproj = filename.ends_with?(".csproj")
      is_program_file = filename.ends_with?("Program.cs") || filename.ends_with?("Startup.cs")
      is_controller = filename.ends_with?(".cs") && filename.includes?("Controller")

      uses_aspnetcore = file_contents.includes?("AspNetCore.Mvc") || # also matches "Microsoft.AspNetCore.Mvc"
                        file_contents.includes?("Microsoft.AspNetCore.App")
      uses_web_sdk = file_contents.includes?("Sdk=\"Microsoft.NET.Sdk.Web\"") ||
                     file_contents.includes?("Sdk=\"Microsoft.NET.Sdk.Razor\"")
      has_mvc_setup = file_contents.includes?("AddControllers") || # also matches "AddControllersWithViews"
                      file_contents.includes?("AddMvc(") ||
                      file_contents.includes?("AddMvcCore") ||
                      file_contents.includes?("MapControllerRoute") ||
                      file_contents.includes?("MapDefaultControllerRoute") ||
                      file_contents.includes?("MapControllers")

      # A pure predicate. It used to push `Program.cs` paths into
      # `CodeLocator` under `cs-aspnet-core-mvc-entrypoints`, which nothing
      # in the tree ever read — the analyzer resolves its entry points
      # through `get_files_by_extension` instead. That write was the only
      # reason this detector declared `idempotent: false`, so the flag goes
      # with it and the detect pass can stop calling this detector once the
      # tech is known.
      (is_csproj && (uses_aspnetcore || uses_web_sdk)) ||
        (is_program_file && (uses_aspnetcore || has_mvc_setup)) ||
        (is_controller && uses_aspnetcore)
    end
  end
end
