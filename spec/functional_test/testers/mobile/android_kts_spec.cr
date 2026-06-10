require "../../func_spec.cr"

# Kotlin-DSL gradle module (build.gradle.kts two directories above the
# manifest). The manifest has no `package` attribute, so the package and
# all `${...}` placeholders resolve from gradle: applicationId, indexed
# manifestPlaceholders["k"] = "v", mapOf("k" to "v") and put("k", "v").
build = ->(url : String, protocol : String) do
  ep = Endpoint.new(url, "GET", [] of Param)
  ep.protocol = protocol
  ep
end

expected_endpoints = [
  # ${authScheme} / ${authHost} from manifestPlaceholders (indexed + mapOf)
  build.call("ktsauth://auth.example.com/callback", "mobile-scheme"),
  # ${legacyScheme} from manifestPlaceholders.put(...)
  build.call("ktslegacy://legacy", "mobile-scheme"),
  # Data-less exported service: package comes from the gradle applicationId
  build.call("intent://com.example.ktsapp/.KtsService", "android-intent"),
  # Navigation deep link whose scheme is ${applicationId}
  build.call("com.example.ktsapp://oauth/callback", "mobile-scheme"),
]

FunctionalTester.new("fixtures/mobile/android_kts/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
