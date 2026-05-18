// Regression guard: Parse Server's `PromiseRouter` exposes
// `this.route('METHOD', '/path', ...)` for route registration.
// Standard verb-DSL extraction doesn't fire on this shape.
class PushAudiencesRouter extends PromiseRouter {
  mountRoutes() {
    this.route('GET', '/push_audiences', req => null);
    this.route('GET', '/push_audiences/:objectId', req => null);
    this.route('POST', '/push_audiences', req => null);
    this.route('PUT', '/push_audiences/:objectId', req => null);
    this.route('DELETE', '/push_audiences/:objectId', req => null);
  }
}
