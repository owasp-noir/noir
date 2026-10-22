require "../../func_spec.cr"

# A destructured `require` whose first binding has a Windows-path default
# (`{ UPLOAD_ROOT = 'C:\\uploads\\', createUploadRouter }`).
#
# The destructuring splitter used to close a quoted run with a one-character
# lookback (`ch == quote && prev_char != '\\'`), which cannot tell an escaped
# quote from an escaped backslash followed by a quote. The `\\'` ending the
# default was read as an escaped quote, the literal never closed, the comma
# after it was never seen, and `createUploadRouter` was never registered as an
# import — so `app.use('/uploads', createUploadRouter())` resolved to nothing
# and both upload routes came out as `/` instead of `/uploads/`.
expected_endpoints = [
  Endpoint.new("/config", "GET"),
  Endpoint.new("/uploads/", "GET"),
  Endpoint.new("/uploads/", "POST"),
]

FunctionalTester.new("fixtures/javascript/express_escaped_backslash_mount/", {
  :techs => 1,
}, expected_endpoints).perform_tests
