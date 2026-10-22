require "../../func_spec.cr"

# A router exported by name and mounted from another file keeps its prefix on
# the sub-routers it mounts itself:
#
#   export const router = express.Router();     // app.use('/api/sd', router)
#   const comfy = express.Router();
#   comfy.post('/ping', ...);
#   router.use('/comfy', comfy);                // served at /api/sd/comfy/ping
#
# The cross-file prefix is recorded under the exported name only, so routes on
# `comfy` were reported at the in-file path `/comfy/ping`, a URL nothing serves.
FunctionalTester.new("fixtures/javascript/express_named_export_nested_router/", {
  :techs     => 1,
  :endpoints => 5,
}, [
  Endpoint.new("/api/sd/top", "GET"),
  Endpoint.new("/api/sd/comfy/ping", "POST"),
  Endpoint.new("/api/sd/comfy/deep/leaf", "GET"),
  Endpoint.new("/api/speech/health", "GET"),
  Endpoint.new("/api/speech/elevenlabs/voices", "POST"),
]).perform_tests
