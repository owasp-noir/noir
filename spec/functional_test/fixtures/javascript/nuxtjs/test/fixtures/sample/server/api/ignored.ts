// Regression guard: a `test/fixtures/<scenario>/server/api/` file is
// a mini-Nuxt fixture used to test the framework, never a real
// endpoint. This URL should NOT appear in the fixture's
// expected-endpoints list.
export default defineEventHandler(() => {
  return { message: "should-not-appear-test-fixture" }
})
