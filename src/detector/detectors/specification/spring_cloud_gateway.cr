require "../../../models/detector"
require "../../../models/code_locator"

module Detector::Specification
  class SpringCloudGateway < Detector
    # Registers Spring Cloud Gateway route config (`spring.cloud.gateway[.server.
    # webflux|.server.webmvc|.mvc].routes`) in Spring Boot config files. The
    # Java/Kotlin `RouteLocatorBuilder` DSL is read by the Spring analyzers.
    detector_for "spring_cloud_gateway", idempotent: false

    CONFIG_FILE = /\A(?:application|bootstrap)(?:[-.][\w.-]*)?\.(?:ya?ml|properties)\z/

    # A `gateway` key (nested or dotted) and a `predicates` key: the two keys
    # every gateway route config carries. A plain Spring Boot config has neither.
    YAML_GATEWAY_KEY    = /^[ \t]*(?:[\w-]+\.)*gateway(?:\.[\w.-]+)?[ \t]*:/m
    YAML_PREDICATES_KEY = /^[ \t]*(?:-[ \t]*)?predicates[ \t]*:/m
    PROPERTIES_ROUTE    = /^[ \t]*spring\.cloud\.gateway(?:\.server\.web(?:flux|mvc)|\.mvc)?\.routes\[\d+\]\.predicates/m

    def applicable?(filename : String) : Bool
      File.basename(filename).matches?(CONFIG_FILE)
    end

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)

      found = if filename.ends_with?(".properties")
                content_matches?(file_contents, PROPERTIES_ROUTE)
              else
                content_matches?(file_contents, YAML_GATEWAY_KEY) && content_matches?(file_contents, YAML_PREDICATES_KEY)
              end
      CodeLocator.instance.push(Noir::LocatorKeys::SPRING_CLOUD_GATEWAY_SPEC, filename) if found
      found
    end
  end
end
