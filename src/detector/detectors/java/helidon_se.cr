require "../../../models/detector"

module Detector::Java
  class HelidonSe < Detector
    detector_for "java_helidon_se", extensions: %w[.java]

    # A class that implements `HttpService` or builds a
    # `HttpRouting.Builder` necessarily imports (or fully qualifies)
    # something under `io.helidon.webserver` — true across Helidon
    # 2.x-4.x, so this single substring check is a real positive
    # signal rather than "any Java file with `.get(...)` calls".
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      file_contents.includes?("io.helidon.webserver")
    end
  end
end
