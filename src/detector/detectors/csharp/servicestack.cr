require "../../../models/detector"

module Detector::CSharp
  class ServiceStack < Detector
    detector_for "cs_servicestack", extensions: %w[.cs .csproj]

    # ServiceStack (https://servicestack.net/) request DTOs are recognized by
    # the `IReturn<T>`/`IReturnVoid` marker interfaces they implement, the
    # `using ServiceStack;` import their file carries, or the fluent
    # `Routes.Add<T>(...)` registration API used from `AppHost.Configure()`.
    def detect(filename : String, file_contents : String) : Bool
      if filename.ends_with?(".csproj")
        return true if file_contents.includes?("Include=\"ServiceStack\"") ||
                       file_contents.includes?("Include='ServiceStack'") ||
                       file_contents.includes?("\"ServiceStack.")
      end

      return false unless filename.ends_with?(".cs")

      return true if file_contents.includes?("using ServiceStack")
      return true if file_contents.includes?(": IReturn<") || file_contents.includes?(", IReturn<")
      return true if file_contents.includes?("IReturnVoid")
      return true if file_contents.includes?("Routes.Add<") || file_contents.includes?("Routes.AddFromAssembly")

      false
    end
  end
end
