require "../../func_spec.cr"

# Regression tests for false positives in the Express/JS route extractor.
#
# Four patterns previously produced spurious routes:
#
# 1. Promise.all([pool.query(SQL), ...])
#    `all` is an HTTP-method token, so fast_scan matched Promise.all([...]).
#    extract_array_paths lacked depth-tracking, so it pulled out bare variable
#    names ("pool", "query") and SQL strings from inside the nested pool.query()
#    arguments, producing routes like GET /pool, GET /query, GET /SELECT COUNT(*)...
#
# 2. axios.get('https://...')
#    Any identifier.http_method('string') matches the fast-scan pattern, so
#    axios.get('https://jsonplaceholder.typicode.com/posts/1') was turned into
#    GET /https://jsonplaceholder.typicode.com/posts/1.
#
# 3. axios.post(`http://.../${var}/...`)
#    Same pattern with a template-literal external URL.
#
# 4. Promise.all(Object.values(...).map(...))
#    `all` matches, the first argument is `Object` (a bare identifier, not a
#    string). resolve_dynamic_path returned the identifier name as-is,
#    producing a /Object route across all seven HTTP methods.
#    Surfaced while running noir on hagopj13/node-express-boilerplate.
#
# The fixture exercises all four patterns. Only the six real routes should appear.

expected_endpoints = [
  Endpoint.new("/health", "GET"),

  # pool.query() inside handler — SQL string must not become a route path
  Endpoint.new("/api/users", "GET"),

  # Promise.all([pool.query(SQL), pool.query(multiline SQL)])
  # Must NOT produce: GET /pool, GET /query, GET /SELECT COUNT(*)..., etc.
  Endpoint.new("/api/stats", "GET"),

  # axios.get('https://...')
  # Must NOT produce a route for the external URL
  Endpoint.new("/api/external", "GET"),

  # axios.post(`http://airflow/...`)
  # Must NOT produce a route for the external URL template
  Endpoint.new("/trigger", "POST", [
    Param.new("dag_id", "", "json"),
  ]),

  # Promise.all(Object.values(...).map(...))
  # Must NOT produce /Object (or any other bare identifier) as a route
  Endpoint.new("/api/stats-nested", "GET"),
]

FunctionalTester.new("fixtures/javascript/express_false_positives/", {
  :techs     => 1,
  :endpoints => 6,
}, expected_endpoints).perform_tests
