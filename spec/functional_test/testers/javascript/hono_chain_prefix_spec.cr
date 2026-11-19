require "../../func_spec.cr"

# Verbs chained on a Hono instance take the instance's prefix:
#
#   const books = new Hono().get('/', h).post('/', h)          // mounted at /api/books
#   const app = new Hono().basePath('/api').route('/books', books)
#   app.get('/endpoint', h).post(h)                             // POST /api/endpoint
#   const v2 = root.basePath('/v2')                             // v2 is prefixed, root is not
#
# Links after the first lost the prefix, a chained `.route()` mounted
# nothing, path-less links were dropped, and `basePath` prefixed `root`.
FunctionalTester.new("fixtures/javascript/hono_chain_prefix/", {
  :techs     => 1,
  :endpoints => 9,
}, [
  Endpoint.new("/api/books/", "GET"),
  Endpoint.new("/api/books/", "POST"),
  Endpoint.new("/api/books/:id", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/endpoint", "GET"),
  Endpoint.new("/api/endpoint", "POST"),
  Endpoint.new("/api/endpoint", "DELETE"),
  Endpoint.new("/ping", "GET"),
  Endpoint.new("/v2/users", "GET"),
]).perform_tests
