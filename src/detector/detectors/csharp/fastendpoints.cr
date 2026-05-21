require "../../../models/detector"

module Detector::CSharp
  class FastEndpoints < Detector
    def detect(filename : String, file_contents : String) : Bool
      is_csproj = filename.ends_with?(".csproj")
      is_cs = filename.ends_with?(".cs")

      if is_csproj
        return true if file_contents.includes?("FastEndpoints")
      end

      if is_cs
        return true if file_contents.includes?("using FastEndpoints")
        return true if file_contents.includes?("FastEndpoints.")
        return true if file_contents.includes?("AddFastEndpoints") || file_contents.includes?("UseFastEndpoints")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs") || filename.ends_with?(".csproj")
    end

    def set_name
      @name = "cs_fastendpoints"
    end
  end
end
