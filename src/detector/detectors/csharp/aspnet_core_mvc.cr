require "../../../models/detector"

module Detector::CSharp
  class AspNetCoreMvc < Detector
    def detect(filename : String, file_contents : String) : Bool
      is_csproj = filename.ends_with?(".csproj")
      is_program_file = filename.ends_with?("Program.cs") || filename.ends_with?("Startup.cs")
      is_controller = filename.ends_with?(".cs") && filename.includes?("Controller")

      uses_aspnetcore = file_contents.includes?("Microsoft.AspNetCore.Mvc") ||
                        file_contents.includes?("Microsoft.AspNetCore.App") ||
                        file_contents.includes?("AspNetCore.Mvc")
      has_mvc_setup = file_contents.includes?("AddControllersWithViews") ||
                      file_contents.includes?("AddControllers") ||
                      file_contents.includes?("MapControllerRoute") ||
                      file_contents.includes?("MapDefaultControllerRoute")

      detected = false
      locator = CodeLocator.instance

      if is_csproj && uses_aspnetcore
        detected = true
      elsif is_program_file && (uses_aspnetcore || has_mvc_setup)
        detected = true
        locator.push("cs-aspnet-core-mvc-entrypoints", filename)
      elsif is_controller && uses_aspnetcore
        detected = true
      end

      detected
    end

    def set_name
      @name = "c#-aspnet-core-mvc"
    end
  end
end
