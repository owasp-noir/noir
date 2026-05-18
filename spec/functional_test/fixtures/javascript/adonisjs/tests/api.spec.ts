// Regression guard: japa / vitest / jest test files (`*.spec.ts`,
// `*.test.ts`) under AdonisJS's `tests/` tree register routes only
// to exercise the framework. None of the URLs below should appear
// in the fixture's expected-endpoints list.
import Route from '@adonisjs/core/services/router'

Route.get('/should-not-appear-test', async () => 'ok')
Route.post('/should-not-appear-test', async () => 'ok')
