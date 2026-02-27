require "../../func_spec.cr"

# Regression tests for false positives in the Express/JS route extractor.
#
# Three patterns previously produced spurious routes:
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
# The fixture exercises all three patterns. Only the five real routes should appear.

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
]

FunctionalTester.new("fixtures/javascript/express_false_positives/", {
  :techs     => 1,
  :endpoints => 5,
}, expected_endpoints).perform_tests
