// Regression guard: hono's own `*.test.ts` suites register routes
// via `app.on('GET', '/path', ...)` to exercise the typing layer.
// The primary route extractor already skips files that match a
// test-stub marker; the auxiliary `extract_on_routes` pass in the
// Hono analyzer has to honor the same gate, or these routes leak
// out as if they were real endpoints. None of the URLs below should
// surface in the fixture's expected-endpoints list.
import { Hono } from 'hono'

const app = new Hono()

app.on('GET', '/should-not-appear-1', (c) => c.json({}))
app.on('GET', '/should-not-appear-2', (c) => c.json({}))
app.on('POST', '/should-not-appear-3', (c) => c.json({}))
